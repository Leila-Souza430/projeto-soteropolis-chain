use anchor_lang::prelude::*;
use anchor_spl::token_interface::{burn_checked, BurnChecked, Mint, Token2022, TokenAccount};

use crate::{constants::*, errors::GreenTokenError, events::TokensBurned, state::Config};

#[derive(Accounts)]
pub struct BurnTokens<'info> {
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

    /// CHECK: The citizen's Web3Auth wallet. Read-only, and never a signer. Its
    /// identity is enforced transitively by `citizen_ata`'s
    /// `associated_token::authority = citizen` constraint below.
    pub citizen: UncheckedAccount<'info>,

    /// Deliberately NOT `init_if_needed` — this account must already exist.
    /// Burning from a nonexistent token account is meaningless, so a missing
    /// account fails loudly during Anchor's account resolution instead.
    #[account(
        mut,
        associated_token::mint = mint,
        associated_token::authority = citizen,
        associated_token::token_program = token_program,
    )]
    pub citizen_ata: InterfaceAccount<'info, TokenAccount>,

    pub token_program: Program<'info, Token2022>,
}

pub fn burn_tokens_handler(ctx: Context<BurnTokens>, amount: u64) -> Result<()> {
    require!(amount > 0, GreenTokenError::InvalidAmount);

    // Redundant with SPL's own check, but gives the backend a specific error
    // code to map to an HTTP 4xx rather than an opaque SPL failure.
    require!(
        ctx.accounts.citizen_ata.amount >= amount,
        GreenTokenError::InsufficientBalance
    );

    let signer_seeds: &[&[&[u8]]] = &[&[CONFIG_SEED, &[ctx.accounts.config.bump]]];

    // Signed by the config PDA acting as the mint's PermanentDelegate. No
    // prior `Approve` from the citizen is required — that is what makes
    // signature-free burns possible.
    burn_checked(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.key(),
            BurnChecked {
                mint: ctx.accounts.mint.to_account_info(),
                from: ctx.accounts.citizen_ata.to_account_info(),
                authority: ctx.accounts.config.to_account_info(),
            },
            signer_seeds,
        ),
        amount,
        GT_DECIMALS,
    )?;

    // Anchor does not refresh already-deserialized accounts after a CPI.
    ctx.accounts.citizen_ata.reload()?;
    let new_balance = ctx.accounts.citizen_ata.amount;

    let config = &mut ctx.accounts.config;
    config.total_burned = config
        .total_burned
        .checked_add(amount)
        .ok_or(GreenTokenError::Overflow)?;

    emit!(TokensBurned {
        citizen: ctx.accounts.citizen.key(),
        amount,
        new_balance,
        total_burned: config.total_burned,
        timestamp: Clock::get()?.unix_timestamp,
    });

    Ok(())
}
