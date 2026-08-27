// Standalone devnet verification: confirms the deployed GT mint really carries
// the Token-2022 PermanentDelegate extension pointing at the Config PDA.
//   node scripts/verify-devnet.js

const { Connection, PublicKey } = require("@solana/web3.js");
const {
  getMint,
  getPermanentDelegate,
  TOKEN_2022_PROGRAM_ID,
} = require("@solana/spl-token");

const PROGRAM_ID = new PublicKey(
  "64FVsreQdM55Gug8t1WsPoK66rUCp6ti4kqfeet2JKTM"
);

(async () => {
  const connection = new Connection(
    process.env.RPC_URL || "https://api.devnet.solana.com",
    "confirmed"
  );

  const [configPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("config")],
    PROGRAM_ID
  );
  const [mintPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("mint")],
    PROGRAM_ID
  );

  const mint = await getMint(
    connection,
    mintPda,
    "confirmed",
    TOKEN_2022_PROGRAM_ID
  );

  const delegate = getPermanentDelegate(mint);

  console.log("program id:        ", PROGRAM_ID.toBase58());
  console.log("config PDA:        ", configPda.toBase58());
  console.log("GT mint:           ", mintPda.toBase58());
  console.log("mint owner program:", TOKEN_2022_PROGRAM_ID.toBase58());
  console.log("decimals:          ", mint.decimals);
  console.log("mint authority:    ", mint.mintAuthority?.toBase58());
  console.log("supply:            ", mint.supply.toString());
  console.log(
    "permanent delegate:",
    delegate ? delegate.delegate.toBase58() : "<MISSING>"
  );

  const ok =
    mint.decimals === 2 &&
    mint.mintAuthority?.equals(configPda) &&
    delegate &&
    delegate.delegate.equals(configPda);

  console.log(ok ? "VERIFY_OK" : "VERIFY_FAILED");
  process.exit(ok ? 0 : 1);
})().catch((e) => {
  console.error("error:", e.message);
  process.exit(1);
});
