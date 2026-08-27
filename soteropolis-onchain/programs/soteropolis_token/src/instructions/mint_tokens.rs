use anchor_lang::prelude::*;
use anchor_spl::{
    associated_token::AssociatedToken,
    token_interface::{mint_to_checked, Mint, MintToChecked, Token2022, TokenAccount},
};

use crate::{constants::*, errors::GreenTokenError, events::TokensMinted, state::Config};

#[derive(Accounts)]
pub struct MintTokens<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = authority @ GreenTokenError::Unauthorized,
        has_one = mint @ GreenTokenError::InvalidMint,
    )]
    pub config: Account<'info, Config>,

    #[account(mut)]
    pub mint: InterfaceAccount<'info, Mint>,

    /// CHECK: The citizen's Web3Auth wallet. Read-only, and never a signer —
    /// the backend is the only signer in this system. Its identity is enforced
    /// transitively by `citizen_ata`'s `associated_token::authority = citizen`
    /// constraint below, which requires `citizen_ata` to be the canonical ATA
    /// derived from (mint, citizen, token_program).
    pub citizen: UncheckedAccount<'info>,

    /// `init_if_needed` is a deliberate, narrow exception to this project's
    /// general prohibition on it. The ATA's address is fully derived from
    /// (mint, owner, token_program) — nothing an attacker can steer — and on
    /// the already-exists path Anchor's `associated_token::*` constraints
    /// verify the derived address plus mint and owner rather than
    /// reinitializing anything. The classic reinitialization attack (resetting
    /// an `authority`-like field) has no analogue in a purely additive
    /// `mint_to` handler.
    #[account(
        init_if_needed,
        payer = authority,
        associated_token::mint = mint,
        associated_token::authority = citizen,
        associated_token::token_program = token_program,
    )]
    pub citizen_ata: InterfaceAccount<'info, TokenAccount>,

    pub token_program: Program<'info, Token2022>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

pub fn mint_tokens_handler(ctx: Context<MintTokens>, amount: u64) -> Result<()> {
    require!(amount > 0, GreenTokenError::InvalidAmount);

    let signer_seeds: &[&[&[u8]]] = &[&[CONFIG_SEED, &[ctx.accounts.config.bump]]];

    mint_to_checked(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.key(),
            MintToChecked {
                mint: ctx.accounts.mint.to_account_info(),
                to: ctx.accounts.citizen_ata.to_account_info(),
                authority: ctx.accounts.config.to_account_info(),
            },
            signer_seeds,
        ),
        amount,
        GT_DECIMALS,
    )?;

    // Anchor does not refresh already-deserialized accounts after a CPI.
    // Without this reload, `.amount` would still report the pre-mint balance.
    ctx.accounts.citizen_ata.reload()?;
    let new_balance = ctx.accounts.citizen_ata.amount;

    let config = &mut ctx.accounts.config;
    config.total_minted = config
        .total_minted
        .checked_add(amount)
        .ok_or(GreenTokenError::Overflow)?;

    emit!(TokensMinted {
        citizen: ctx.accounts.citizen.key(),
        amount,
        new_balance,
        total_minted: config.total_minted,
        timestamp: Clock::get()?.unix_timestamp,
    });

    Ok(())
}
