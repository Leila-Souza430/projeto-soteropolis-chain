use anchor_lang::prelude::*;

/// Global program configuration.
///
/// A singleton PDA at seeds `[b"config"]`. It is the GT mint authority and the
/// mint's Token-2022 `PermanentDelegate`, which is what lets the backend burn
/// from any citizen's token account without that citizen signing.
#[account]
#[derive(InitSpace)]
pub struct Config {
    /// Backend signer permitted to call `mint_tokens` / `burn_tokens`.
    pub authority: Pubkey,
    /// The GT Token-2022 mint this config governs.
    pub mint: Pubkey,
    /// Cumulative GT minted, in base units.
    pub total_minted: u64,
    /// Cumulative GT burned, in base units.
    pub total_burned: u64,
    /// Canonical bump, stored so it is never recomputed.
    pub bump: u8,
    /// Config schema version.
    pub version: u8,
}
