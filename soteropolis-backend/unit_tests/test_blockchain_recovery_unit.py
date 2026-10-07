import os
from base64 import b64decode
from types import SimpleNamespace

os.environ.update(
    {
        "SUPABASE_URL": "http://127.0.0.1:54321",
        "SUPABASE_SERVICE_ROLE_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.fake",
        "SUPABASE_ANON_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.fake",
        "TOKEN_RATE_PER_KG": "10",
        "TOKEN_FIXED_AMOUNT": "10",
    }
)

import pytest
from solders.hash import Hash
from solders.instruction import Instruction
from solders.keypair import Keypair
from solders.pubkey import Pubkey
from solders.signature import Signature
from solders.transaction import Transaction
from solders.transaction_status import TransactionConfirmationStatus

from services.blockchain import (
    BlockchainError,
    BlockchainNeedsReconciliation,
    PreparedTransaction,
    SolanaBlockchainService,
)


def _status(*, err=None, confirmation_status=TransactionConfirmationStatus.Confirmed):
    return SimpleNamespace(err=err, confirmation_status=confirmation_status)


class _FakeRpc:
    def __init__(self, *, statuses=None, block_height=10, confirm_status=None):
        self.statuses = statuses or [None]
        self.block_height = block_height
        self.confirm_status = confirm_status or _status()
        self.sent_bytes = []

    def get_signature_statuses(self, _signatures, search_transaction_history=False):
        return SimpleNamespace(value=self.statuses)

    def get_block_height(self, commitment):
        return SimpleNamespace(value=self.block_height)

    def send_raw_transaction(self, raw_bytes, opts):
        self.sent_bytes.append(raw_bytes)
        transaction = Transaction.from_bytes(raw_bytes)
        return SimpleNamespace(value=transaction.signatures[0])

    def confirm_transaction(self, signature, commitment):
        return SimpleNamespace(value=[self.confirm_status])

    def get_latest_blockhash(self, commitment):
        return SimpleNamespace(
            value=SimpleNamespace(blockhash=Hash.default(), last_valid_block_height=321)
        )


def _service(rpc):
    service = object.__new__(SolanaBlockchainService)
    service._client = rpc
    service._commitment = "confirmed"
    service._authority = Keypair()
    return service


def _prepared(service):
    instruction = Instruction(Pubkey.default(), b"burn-test", [])
    return service._prepare_instruction(instruction)


def test_prepare_signs_and_serializes_without_broadcasting():
    rpc = _FakeRpc()
    service = _service(rpc)

    prepared = _prepared(service)
    transaction = Transaction.from_bytes(b64decode(prepared.serialized_transaction))

    assert str(transaction.signatures[0]) == prepared.signature
    assert prepared.last_valid_block_height == 321
    assert rpc.sent_bytes == []


def test_existing_confirmed_signature_is_reused_without_rebroadcast():
    rpc = _FakeRpc(statuses=[_status()])
    service = _service(rpc)
    prepared = _prepared(service)

    assert service.submit_prepared_transaction(prepared) == prepared.signature
    assert rpc.sent_bytes == []


def test_missing_signature_rebroadcasts_exact_same_signed_bytes():
    rpc = _FakeRpc(statuses=[None], block_height=100)
    service = _service(rpc)
    prepared = _prepared(service)
    original_bytes = b64decode(prepared.serialized_transaction)

    assert service.submit_prepared_transaction(prepared) == prepared.signature
    assert rpc.sent_bytes == [original_bytes]


def test_expired_unconfirmed_transaction_requires_reconciliation():
    rpc = _FakeRpc(statuses=[None], block_height=322)
    service = _service(rpc)
    prepared = _prepared(service)

    with pytest.raises(BlockchainNeedsReconciliation):
        service.submit_prepared_transaction(prepared)

    assert rpc.sent_bytes == []


def test_confirmed_on_chain_failure_is_never_reported_as_success():
    rpc = _FakeRpc(statuses=[_status(err="program failure")])
    service = _service(rpc)
    prepared = _prepared(service)

    with pytest.raises(BlockchainError, match="Transaction failed"):
        service.submit_prepared_transaction(prepared)

    assert rpc.sent_bytes == []


def test_prepared_transaction_signature_must_match_signed_wire_bytes():
    rpc = _FakeRpc()
    service = _service(rpc)
    prepared = _prepared(service)
    corrupted = PreparedTransaction(
        signature=str(Signature.default()),
        serialized_transaction=prepared.serialized_transaction,
        last_valid_block_height=prepared.last_valid_block_height,
    )

    with pytest.raises(BlockchainError, match="signature does not match"):
        service.submit_prepared_transaction(corrupted)

    assert rpc.sent_bytes == []
