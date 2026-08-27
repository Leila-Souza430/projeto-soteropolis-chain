use anchor_lang::prelude::*;

#[event]
pub struct TokensMinted {
    pub citizen: Pubkey,
    pub amount: u64,
    pub new_balance: u64,
    pub total_minted: u64,
    pub timestamp: i64,
}

#[event]
pub struct TokensBurned {
    pub citizen: Pubkey,
    pub amount: u64,
    pub new_balance: u64,
    pub total_burned: u64,
    pub timestamp: i64,
}
