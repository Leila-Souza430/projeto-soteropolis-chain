pub mod burn_tokens;
pub mod initialize;
pub mod mint_tokens;

// Glob re-exports are required: `#[program]` resolves the `__client_accounts_*`
// modules that `#[derive(Accounts)]` generates through the crate root. Each
// handler is named distinctly so these globs stay unambiguous.
pub use burn_tokens::*;
pub use initialize::*;
pub use mint_tokens::*;
