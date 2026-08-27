/// GT is denominated with 2 decimals, so 1 GT == 100 base units.
pub const GT_DECIMALS: u8 = 2;

/// Seed of the singleton config PDA.
pub const CONFIG_SEED: &[u8] = b"config";

/// Seed of the GT mint PDA.
pub const MINT_SEED: &[u8] = b"mint";
