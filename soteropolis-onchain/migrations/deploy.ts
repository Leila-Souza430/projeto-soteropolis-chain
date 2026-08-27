// Invoked by `anchor migrate`. Creates the Config PDA and the GT Token-2022
// mint, then prints the addresses the backend needs.
//
// Safe to re-run: `initialize` uses plain `init`, so a second call would fail
// with "account already in use". This script detects an existing config and
// skips instead of erroring.

import * as anchor from "@anchor-lang/core";
import { Program } from "@anchor-lang/core";
import { PublicKey } from "@solana/web3.js";
import { TOKEN_2022_PROGRAM_ID } from "@solana/spl-token";
import { SoteropolisToken } from "../target/types/soteropolis_token";

module.exports = async function (provider: anchor.AnchorProvider) {
  anchor.setProvider(provider);

  const program = anchor.workspace
    .soteropolisToken as Program<SoteropolisToken>;

  const [configPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("config")],
    program.programId
  );
  const [mintPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("mint")],
    program.programId
  );

  const existing = await provider.connection.getAccountInfo(configPda);

  if (existing) {
    console.log("Config already initialized — skipping.");
  } else {
    const sig = await program.methods
      .initialize()
      // `accountsPartial` rather than `accounts`: Anchor 1.0 auto-resolves the
      // config and mint PDAs from their seeds, and `accounts` rejects any
      // account it can derive itself.
      .accountsPartial({
        authority: provider.wallet.publicKey,
        config: configPda,
        mint: mintPda,
        tokenProgram: TOKEN_2022_PROGRAM_ID,
      })
      .rpc();
    console.log("initialize signature:", sig);
  }

  const config = await program.account.config.fetch(configPda);

  console.log("---- Soteropolis GT deployment ----");
  console.log("program id:   ", program.programId.toBase58());
  console.log("config PDA:   ", configPda.toBase58());
  console.log("GT mint:      ", mintPda.toBase58());
  console.log("authority:    ", config.authority.toBase58());
  console.log("version:      ", config.version);
  console.log("total minted: ", config.totalMinted.toString());
  console.log("total burned: ", config.totalBurned.toString());
};
