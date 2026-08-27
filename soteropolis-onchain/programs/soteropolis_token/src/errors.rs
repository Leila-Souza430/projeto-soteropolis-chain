use anchor_lang::prelude::*;

#[error_code]
pub enum GreenTokenError {
    #[msg("Invalid authority")]
    Unauthorized,
    #[msg("Mint account does not match config")]
    InvalidMint,
    #[msg("Citizen balance is insufficient for this burn")]
    InsufficientBalance,
    #[msg("Amount must be greater than zero")]
    InvalidAmount,
    #[msg("Arithmetic overflow")]
    Overflow,
}
