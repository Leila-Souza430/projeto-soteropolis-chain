use anchor_lang::prelude::*;
use anchor_spl::token_interface::{Mint, Token2022};

use crate::{constants::*, state::Config};

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    /// Plain `init`, never `init_if_needed`: a second call fails with "account
    /// already in use", which is precisely the reinitialization guard this
    /// account needs — re-running it would otherwise overwrite `authority`.
    #[account(
        init,
        payer = authority,
        space = Config::DISCRIMINATOR.len() + Config::INIT_SPACE,
        seeds = [CONFIG_SEED],
        bump
    )]
    pub config: Account<'info, Config>,

    /// The GT mint. `extensions::permanent_delegate::delegate = config` writes
    /// the Token-2022 PermanentDelegate extension at creation, making the
    /// config PDA a permanent delegate over every account of this mint. That
    /// is what lets `burn_tokens` run without any per-holder `Approve`.
    #[account(
        init,
        payer = authority,
        seeds = [MINT_SEED],
        bump,
        mint::decimals = GT_DECIMALS,
        mint::authority = config,
        extensions::permanent_delegate::delegate = config,
    )]
    pub mint: InterfaceAccount<'info, Mint>,

    pub token_program: Program<'info, Token2022>,
    pub system_program: Program<'info, System>,
}

pub fn initialize_handler(ctx: Context<Initialize>) -> Result<()> {
    let config = &mut ctx.accounts.config;

    config.authority = ctx.accounts.authority.key();
    config.mint = ctx.accounts.mint.key();
    config.total_minted = 0;
    config.total_burned = 0;
    config.bump = ctx.bumps.config;
    config.version = 1;

    Ok(())
}
