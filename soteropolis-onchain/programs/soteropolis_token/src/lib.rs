// Anchor's `#[program]` expansion trips this lint inside macro-generated code;
// there is nothing to fix in this crate's own sources.
#![allow(clippy::diverging_sub_expression)]

pub mod constants;
pub mod errors;
pub mod events;
pub mod instructions;
pub mod state;

use anchor_lang::prelude::*;

pub use constants::*;
pub use instructions::*;
pub use state::*;

declare_id!("64FVsreQdM55Gug8t1WsPoK66rUCp6ti4kqfeet2JKTM");

/// Green Token (GT) for the Soteropolis Chain recycling-rewards platform.
///
/// Citizens hold invisible Web3Auth wallets and never sign anything; the
/// backend `authority` is the only signer. Signature-free burns are possible
/// because the GT mint carries the Token-2022 `PermanentDelegate` extension
/// pointing at the config PDA, granting it burn rights over every holder's
/// account of this mint.
#[program]
pub mod soteropolis_token {
    use super::*;

    /// One-time bootstrap: creates the config PDA and the GT Token-2022 mint.
    pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
        instructions::initialize::initialize_handler(ctx)
    }

    /// Credits `amount` base units of GT to a citizen's ATA. Backend-only.
    pub fn mint_tokens(ctx: Context<MintTokens>, amount: u64) -> Result<()> {
        instructions::mint_tokens::mint_tokens_handler(ctx, amount)
    }

    /// Burns `amount` base units of GT from a citizen's ATA. Backend-only.
    pub fn burn_tokens(ctx: Context<BurnTokens>, amount: u64) -> Result<()> {
        instructions::burn_tokens::burn_tokens_handler(ctx, amount)
    }
}
