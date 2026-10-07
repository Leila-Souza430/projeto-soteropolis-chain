"""
Blockchain integration layer.

Phase 2 shipped a deterministic mock. Phase 3 adds the real Solana
implementation behind the same BlockchainService interface, so routers
never need to change now that on-chain minting/burning has landed.
"""

import base64
import hashlib
import json
from abc import ABC, abstractmethod
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

from solana.rpc.api import Client
from solana.rpc.core import RPCException, TransactionExpiredBlockheightExceededError, UnconfirmedTxError
from solana.rpc.types import TxOpts
from solders.instruction import AccountMeta, Instruction
from solders.keypair import Keypair
from solders.pubkey import Pubkey
from solders.signature import Signature
from solders.system_program import ID as SYSTEM_PROGRAM_ID
from solders.transaction import Transaction

from config import settings

# Well-known, network-wide SPL program IDs. These are not deployment-specific
# (identical on mainnet/devnet/testnet), so unlike the program ID and mint
# address they are not sourced from config.
TOKEN_2022_PROGRAM_ID = Pubkey.from_string("TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb")
ASSOCIATED_TOKEN_PROGRAM_ID = Pubkey.from_string("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")

# Anchor 1.0 instruction discriminators: sha256("global:<instruction_name>")[:8].
_MINT_TOKENS_DISCRIMINATOR = hashlib.sha256(b"global:mint_tokens").digest()[:8]
_BURN_TOKENS_DISCRIMINATOR = hashlib.sha256(b"global:burn_tokens").digest()[:8]

# soteropolis-onchain program's #[error_code] enum (see .claude/rules/anchor.md).
_PROGRAM_ERROR_MESSAGES = {
    6000: "Unauthorized",
    6001: "InvalidMint",
    6002: "InsufficientBalance",
    6003: "InvalidAmount",
    6004: "Overflow",
}


class BlockchainService(ABC):
    @abstractmethod
    def mint_tokens(self, wallet_address: str, quantidade: float, idempotency_key: str) -> str:
        """Credit `quantidade` tokens to `wallet_address`. Returns the tx_hash."""
        ...

    @abstractmethod
    def burn_tokens(self, wallet_address: str, quantidade: float, idempotency_key: str) -> str:
        """Debit `quantidade` tokens from `wallet_address`. Returns the tx_hash."""
        ...

    def prepare_burn_transaction(
        self, wallet_address: str, quantidade: float, idempotency_key: str
    ) -> PreparedTransaction:
        raise NotImplementedError("This blockchain service cannot prepare recoverable burns")

    def submit_prepared_transaction(self, prepared: PreparedTransaction) -> str:
        raise NotImplementedError("This blockchain service cannot submit prepared transactions")


class BlockchainError(Exception):
    """
    Raised by SolanaBlockchainService when an instruction cannot be built,
    fails RPC preflight simulation, or fails on-chain after confirmation.

    Routers do not catch this specially (see routers/descartes.py) - it
    propagates to FastAPI's default handler as a 500, the same outcome a
    blockchain call failure would have had before Phase 3, since
    MockBlockchainService could never fail.
    """


class BlockchainOutcomeUnknown(BlockchainError):
    """The RPC did not establish whether a signed transaction was committed."""


class BlockchainNeedsReconciliation(BlockchainOutcomeUnknown):
    """The transaction expired without enough RPC history to prove its outcome."""


class BlockchainTransactionFailed(BlockchainError):
    """The chain definitively rejected or failed the signed transaction."""


@dataclass(frozen=True)
class PreparedTransaction:
    signature: str
    serialized_transaction: str
    last_valid_block_height: int


class MockBlockchainService(BlockchainService):
    """
    No real chain call - the tx_hash is derived deterministically from the
    idempotency_key instead.

    This determinism is the core of the idempotency design: if a caller (or
    a network retry) sends the same Idempotency-Key twice, this method
    returns the exact same tx_hash both times. Combined with the UNIQUE
    constraint on transacoes_tokens.tx_hash, a second insert attempt then
    fails with a Postgres 23505 conflict instead of silently minting/
    crediting twice - the router catches that conflict and replays the
    already-recorded transaction (Stripe-style idempotency key pattern).

    The "mint:"/"burn:" prefix keeps the two operations from ever colliding
    on the same idempotency key.
    """

    def mint_tokens(self, wallet_address: str, quantidade: float, idempotency_key: str) -> str:
        return hashlib.sha256(f"mock:mint:{idempotency_key}".encode()).hexdigest()

    def burn_tokens(self, wallet_address: str, quantidade: float, idempotency_key: str) -> str:
        return hashlib.sha256(f"mock:burn:{idempotency_key}".encode()).hexdigest()

    def prepare_burn_transaction(
        self, wallet_address: str, quantidade: float, idempotency_key: str
    ) -> PreparedTransaction:
        signature = hashlib.sha256(f"mock:burn:{idempotency_key}".encode()).hexdigest()
        serialized = base64.b64encode(f"mock:{signature}".encode()).decode("ascii")
        return PreparedTransaction(signature, serialized, 0)

    def submit_prepared_transaction(self, prepared: PreparedTransaction) -> str:
        return prepared.signature


def _quantidade_to_base_units(quantidade: float, decimals: int) -> int:
    """
    Convert a float GT amount to integer base units at `decimals` precision.

    Uses Decimal(str(quantidade)) rather than int(quantidade * 100): the
    latter has float-precision bugs (e.g. 1.37 * 100 is 136.99999999999997
    in binary floating point, not 137.0).
    """
    try:
        exact = Decimal(str(quantidade))
    except InvalidOperation as exc:
        raise BlockchainError(f"quantidade is not a valid decimal number: {quantidade!r}") from exc

    base_units = (exact * (Decimal(10) ** decimals)).quantize(Decimal(1), rounding=ROUND_HALF_UP)
    base_units_int = int(base_units)

    if base_units_int <= 0:
        raise BlockchainError(
            f"quantidade must convert to a positive base-unit amount at {decimals} decimals, "
            f"got {quantidade!r} -> {base_units_int}"
        )
    return base_units_int


def _derive_citizen_ata(citizen: Pubkey, mint: Pubkey) -> Pubkey:
    """Token-2022-aware Associated Token Account address for (mint, citizen)."""
    ata, _bump = Pubkey.find_program_address(
        [bytes(citizen), bytes(TOKEN_2022_PROGRAM_ID), bytes(mint)],
        ASSOCIATED_TOKEN_PROGRAM_ID,
    )
    return ata


def _extract_custom_error_code(tx_error) -> int | None:
    """Best-effort pull of an Anchor custom error code out of a solders TransactionErrorType."""
    instruction_error = getattr(tx_error, "err", None)
    return getattr(instruction_error, "code", None)


def _describe_chain_error(tx_error, logs: list[str] | None = None) -> str:
    code = _extract_custom_error_code(tx_error)
    if code is not None:
        name = _PROGRAM_ERROR_MESSAGES.get(code, "UnknownProgramError")
        message = f"Program error {code} ({name})"
    else:
        message = f"Transaction failed: {tx_error}"

    if logs:
        anchor_lines = [line for line in logs if "Error Message" in line or "AnchorError" in line]
        if anchor_lines:
            message += " - " + " | ".join(anchor_lines)
    return message


class SolanaBlockchainService(BlockchainService):
    """
    Calls the deployed Anchor program's mint_tokens/burn_tokens instructions
    directly, via manually-built instructions (solders + solana-py's
    synchronous Client). Not anchorpy - incompatible with Anchor 1.0's IDL
    format.

    The GT mint's PermanentDelegate is the Config PDA, so the citizen never
    signs mint_tokens or burn_tokens - only this service's authority keypair
    does. Both instructions work against any syntactically valid citizen
    pubkey, whether or not anyone controls its private key.
    """

    def __init__(self) -> None:
        for field in (
            "solana_rpc_url",
            "solana_program_id",
            "solana_gt_mint_address",
            "solana_authority_keypair_path",
        ):
            if not getattr(settings, field):
                raise BlockchainError(f"{field} is not configured (required when BLOCKCHAIN_MODE=solana)")

        self._client = Client(settings.solana_rpc_url)
        self._commitment = settings.solana_commitment
        self._decimals = settings.solana_gt_decimals

        self._program_id = Pubkey.from_string(settings.solana_program_id)
        self._mint = Pubkey.from_string(settings.solana_gt_mint_address)
        # Config PDA is always re-derived (never hardcoded/configured) - it's
        # fully determined by the program ID, so there is no separate value
        # that could ever drift out of sync.
        self._config, _bump = Pubkey.find_program_address([b"config"], self._program_id)

        self._authority = self._load_authority_keypair(settings.solana_authority_keypair_path)

    @staticmethod
    def _load_authority_keypair(path: str) -> Keypair:
        try:
            with open(path, encoding="utf-8") as f:
                raw_secret_key = json.load(f)
            return Keypair.from_bytes(bytes(raw_secret_key))
        except (OSError, ValueError) as exc:
            raise BlockchainError(f"Failed to load authority keypair from {path!r}: {exc}") from exc

    @staticmethod
    def _validate_citizen_pubkey(wallet_address: str) -> Pubkey:
        """
        Parse `wallet_address` and require it to be a real, on-curve ed25519
        pubkey, before mint_tokens/burn_tokens do anything else.

        The on-chain program accepts any 32 bytes as `citizen` with no
        validation (its PermanentDelegate authority is enough to mint/burn
        without the citizen ever signing - see the module docstring). An
        off-curve address has no corresponding keypair, so a backend bug
        that mints there would credit tokens nobody can ever spend. Caught
        here, backend-side, per the on-chain audit finding.
        """
        try:
            citizen = Pubkey.from_string(wallet_address)
        except ValueError as exc:
            raise BlockchainError(f"wallet_address is not a valid base58 pubkey: {wallet_address!r}") from exc

        if not citizen.is_on_curve():
            raise BlockchainError(f"wallet_address is not a valid on-curve pubkey: {wallet_address!r}")

        return citizen

    def mint_tokens(self, wallet_address: str, quantidade: float, idempotency_key: str) -> str:
        return self._send_instruction(
            discriminator=_MINT_TOKENS_DISCRIMINATOR,
            wallet_address=wallet_address,
            quantidade=quantidade,
            include_ata_creation_accounts=True,
        )

    def burn_tokens(self, wallet_address: str, quantidade: float, idempotency_key: str) -> str:
        return self._send_instruction(
            discriminator=_BURN_TOKENS_DISCRIMINATOR,
            wallet_address=wallet_address,
            quantidade=quantidade,
            include_ata_creation_accounts=False,
        )

    def prepare_burn_transaction(
        self, wallet_address: str, quantidade: float, idempotency_key: str
    ) -> PreparedTransaction:
        instruction = self._build_instruction(
            discriminator=_BURN_TOKENS_DISCRIMINATOR,
            wallet_address=wallet_address,
            quantidade=quantidade,
            include_ata_creation_accounts=False,
        )
        return self._prepare_instruction(instruction)

    def _send_instruction(
        self,
        *,
        discriminator: bytes,
        wallet_address: str,
        quantidade: float,
        include_ata_creation_accounts: bool,
    ) -> str:
        instruction = self._build_instruction(
            discriminator=discriminator,
            wallet_address=wallet_address,
            quantidade=quantidade,
            include_ata_creation_accounts=include_ata_creation_accounts,
        )
        return self.submit_prepared_transaction(self._prepare_instruction(instruction))

    def _build_instruction(
        self,
        *,
        discriminator: bytes,
        wallet_address: str,
        quantidade: float,
        include_ata_creation_accounts: bool,
    ) -> Instruction:
        # Shared by mint_tokens and burn_tokens (both funnel through this
        # method) - validated before anything else below (amount
        # conversion, ATA derivation, RPC calls).
        citizen = self._validate_citizen_pubkey(wallet_address)

        amount = _quantidade_to_base_units(quantidade, self._decimals)
        citizen_ata = _derive_citizen_ata(citizen, self._mint)

        # Account order per the deployed program's IDL (see task facts) -
        # mint_tokens additionally needs associated_token_program +
        # system_program because it creates the citizen ATA on demand;
        # burn_tokens requires the ATA to already exist.
        accounts = [
            AccountMeta(self._authority.pubkey(), is_signer=True, is_writable=True),
            AccountMeta(self._config, is_signer=False, is_writable=True),
            AccountMeta(self._mint, is_signer=False, is_writable=True),
            AccountMeta(citizen, is_signer=False, is_writable=False),
            AccountMeta(citizen_ata, is_signer=False, is_writable=True),
            AccountMeta(TOKEN_2022_PROGRAM_ID, is_signer=False, is_writable=False),
        ]
        if include_ata_creation_accounts:
            accounts.append(AccountMeta(ASSOCIATED_TOKEN_PROGRAM_ID, is_signer=False, is_writable=False))
            accounts.append(AccountMeta(SYSTEM_PROGRAM_ID, is_signer=False, is_writable=False))

        instruction = Instruction(self._program_id, discriminator + amount.to_bytes(8, "little"), accounts)
        return instruction

    def _prepare_instruction(self, instruction: Instruction) -> PreparedTransaction:
        try:
            blockhash_resp = self._client.get_latest_blockhash(commitment=self._commitment)
            txn = Transaction.new_signed_with_payer(
                [instruction],
                self._authority.pubkey(),
                [self._authority],
                blockhash_resp.value.blockhash,
            )
        except RPCException as exc:
            raise BlockchainError(self._describe_rpc_exception(exc)) from exc
        return PreparedTransaction(
            signature=str(txn.signatures[0]),
            serialized_transaction=base64.b64encode(bytes(txn)).decode("ascii"),
            last_valid_block_height=blockhash_resp.value.last_valid_block_height,
        )

    def submit_prepared_transaction(self, prepared: PreparedTransaction) -> str:
        try:
            signature = Signature.from_string(prepared.signature)
            serialized = base64.b64decode(prepared.serialized_transaction, validate=True)
            transaction = Transaction.from_bytes(serialized)
        except (ValueError, TypeError) as exc:
            raise BlockchainError("Prepared Solana transaction is malformed") from exc

        if not transaction.signatures or str(transaction.signatures[0]) != str(signature):
            raise BlockchainError("Prepared transaction signature does not match its wire data")

        try:
            status_resp = self._client.get_signature_statuses(
                [signature], search_transaction_history=True
            )
            chain_status = status_resp.value[0] if status_resp.value else None
            if chain_status is not None:
                return self._confirm_existing(signature, chain_status)

            current_height = self._client.get_block_height(commitment=self._commitment).value
            if current_height > prepared.last_valid_block_height:
                status_resp = self._client.get_signature_statuses(
                    [signature], search_transaction_history=True
                )
                chain_status = status_resp.value[0] if status_resp.value else None
                if chain_status is None:
                    raise BlockchainNeedsReconciliation(
                        "The transaction blockhash expired and its outcome could not be verified"
                    )
                return self._confirm_existing(signature, chain_status)

            send_resp = self._client.send_raw_transaction(
                serialized,
                TxOpts(
                    skip_preflight=False,
                    skip_confirmation=True,
                    preflight_commitment=self._commitment,
                ),
            )
            if str(send_resp.value) != str(signature):
                raise BlockchainOutcomeUnknown(
                    "RPC returned a different signature for the persisted transaction"
                )
            status_resp = self._client.confirm_transaction(
                signature,
                commitment=self._commitment,
            )
        except RPCException as exc:
            payload = exc.args[0] if exc.args else None
            data = getattr(payload, "data", None)
            tx_error = getattr(data, "err", None)
            if tx_error is not None:
                raise BlockchainTransactionFailed(
                    _describe_chain_error(tx_error, getattr(data, "logs", None))
                ) from exc
            raise BlockchainOutcomeUnknown(
                f"Could not determine prepared transaction outcome: {self._describe_rpc_exception(exc)}"
            ) from exc
        except (UnconfirmedTxError, TransactionExpiredBlockheightExceededError) as exc:
            raise BlockchainOutcomeUnknown(
                f"Could not confirm prepared transaction outcome: {exc}"
            ) from exc

        chain_status = status_resp.value[0] if status_resp.value else None
        if chain_status is None:
            raise BlockchainOutcomeUnknown(
                "RPC returned no transaction status after confirmation"
            )
        return self._confirm_existing(signature, chain_status)

    def _confirm_existing(self, signature: Signature, chain_status) -> str:
        if chain_status.err is not None:
            raise BlockchainTransactionFailed(_describe_chain_error(chain_status.err))

        confirmation_status = chain_status.confirmation_status
        required_rank = {"processed": 0, "confirmed": 1, "finalized": 2}.get(
            self._commitment
        )
        if required_rank is None:
            raise BlockchainError(f"Unsupported Solana commitment: {self._commitment!r}")

        if confirmation_status is not None and int(confirmation_status) >= required_rank:
            return str(signature)

        try:
            response = self._client.confirm_transaction(
                signature,
                commitment=self._commitment,
            )
        except RPCException as exc:
            raise BlockchainOutcomeUnknown(
                f"Could not confirm transaction outcome: {self._describe_rpc_exception(exc)}"
            ) from exc
        except (UnconfirmedTxError, TransactionExpiredBlockheightExceededError) as exc:
            raise BlockchainOutcomeUnknown(
                f"Could not confirm transaction outcome: {exc}"
            ) from exc

        confirmed_status = response.value[0] if response.value else None
        if confirmed_status is None:
            raise BlockchainOutcomeUnknown(
                "RPC returned no transaction status after confirmation"
            )
        if confirmed_status.err is not None:
            raise BlockchainTransactionFailed(_describe_chain_error(confirmed_status.err))
        if (
            confirmed_status.confirmation_status is None
            or int(confirmed_status.confirmation_status) < required_rank
        ):
            raise BlockchainOutcomeUnknown(
                "Transaction has not reached the configured commitment"
            )
        return str(signature)

    @staticmethod
    def _describe_rpc_exception(exc: RPCException) -> str:
        payload = exc.args[0] if exc.args else None
        data = getattr(payload, "data", None)
        tx_error = getattr(data, "err", None)
        if tx_error is not None:
            return _describe_chain_error(tx_error, getattr(data, "logs", None))
        return str(getattr(payload, "message", None) or exc)


def get_blockchain_service() -> BlockchainService:
    """Factory selecting the blockchain backend from settings.blockchain_mode."""
    if settings.blockchain_mode == "mock":
        return MockBlockchainService()
    if settings.blockchain_mode == "solana":
        return SolanaBlockchainService()
    raise ValueError(f"Unknown blockchain_mode: {settings.blockchain_mode!r}")
