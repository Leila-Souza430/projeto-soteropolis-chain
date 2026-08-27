"""
Lightweight, service-level coverage for Task 2 Check A, supplementing the
HTTP-level E2E flows in the other test modules. (Check B - the mint cap -
is already covered at the HTTP level by
test_e2e_happy_path.test_descarte_over_mint_cap_is_rejected.)

Check A validates before any RPC call is made (see
SolanaBlockchainService._validate_citizen_pubkey), so these two cases are
safe to run directly against mint_tokens/burn_tokens with no real devnet
transaction involved. There is also no way to exercise this through the
FastAPI app: wallet_address always comes from the authenticated citizen's
own linked users.wallet_address row, never from the request body.
"""

import pytest
from solders.pubkey import Pubkey
from solders.system_program import ID as SYSTEM_PROGRAM_ID

from services.blockchain import BlockchainError, SolanaBlockchainService


@pytest.fixture(scope="module")
def blockchain_service() -> SolanaBlockchainService:
    return SolanaBlockchainService()


def test_mint_tokens_rejects_malformed_wallet_address(blockchain_service):
    with pytest.raises(BlockchainError):
        blockchain_service.mint_tokens("not-a-valid-base58-pubkey", 1.0, "e2e-security-malformed")


def test_burn_tokens_rejects_off_curve_wallet_address(blockchain_service):
    # A PDA is off-curve by construction - find_program_address explicitly
    # searches for a bump that lands off the curve, so this is a real
    # address with no corresponding private key, exactly what Check A must
    # reject.
    off_curve_pda, _bump = Pubkey.find_program_address([b"e2e-test-off-curve"], SYSTEM_PROGRAM_ID)
    assert not off_curve_pda.is_on_curve()  # sanity check on the fixture itself

    with pytest.raises(BlockchainError):
        blockchain_service.burn_tokens(str(off_curve_pda), 1.0, "e2e-security-off-curve")
