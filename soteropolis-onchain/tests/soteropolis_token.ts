import * as anchor from "@anchor-lang/core";
import { Program } from "@anchor-lang/core";
import {
  PublicKey,
  Keypair,
  SystemProgram,
  Transaction,
  LAMPORTS_PER_SOL,
} from "@solana/web3.js";
import {
  TOKEN_2022_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
  getAssociatedTokenAddressSync,
  getMint,
  getPermanentDelegate,
  getAccount,
  createMint,
  createAssociatedTokenAccount,
} from "@solana/spl-token";
import { assert } from "chai";
import { SoteropolisToken } from "../target/types/soteropolis_token";

describe("soteropolis_token", () => {
  anchor.setProvider(anchor.AnchorProvider.env());

  const provider = anchor.getProvider() as anchor.AnchorProvider;
  const program = anchor.workspace.soteropolisToken as Program<SoteropolisToken>;
  const authority = provider.wallet.publicKey;

  const [configPda, configBump] = PublicKey.findProgramAddressSync(
    [Buffer.from("config")],
    program.programId
  );
  const [mintPda] = PublicKey.findProgramAddressSync(
    [Buffer.from("mint")],
    program.programId
  );

  // A stand-in for a citizen's invisible Web3Auth wallet. It never signs.
  const citizen = Keypair.generate().publicKey;
  const citizenAta = getAssociatedTokenAddressSync(
    mintPda,
    citizen,
    true,
    TOKEN_2022_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID
  );

  const MINT_AMOUNT = new anchor.BN(10_000); // 100.00 GT at 2 decimals
  const BURN_AMOUNT = new anchor.BN(2_500); //  25.00 GT

  // --- shared helpers -------------------------------------------------------

  /** Canonical GT ATA for a citizen. */
  const ataOf = (owner: PublicKey): PublicKey =>
    getAssociatedTokenAddressSync(
      mintPda,
      owner,
      true,
      TOKEN_2022_PROGRAM_ID,
      ASSOCIATED_TOKEN_PROGRAM_ID
    );

  const gtSupply = async (): Promise<bigint> =>
    (await getMint(provider.connection, mintPda, undefined, TOKEN_2022_PROGRAM_ID))
      .supply;

  const gtBalance = async (ata: PublicKey): Promise<bigint> =>
    (await getAccount(provider.connection, ata, undefined, TOKEN_2022_PROGRAM_ID))
      .amount;

  /** Creates a keypair funded from the provider wallet (surfpool has no faucet dependency). */
  const fundedKeypair = async (sol = 2): Promise<Keypair> => {
    const kp = Keypair.generate();
    const tx = new Transaction().add(
      SystemProgram.transfer({
        fromPubkey: authority,
        toPubkey: kp.publicKey,
        lamports: sol * LAMPORTS_PER_SOL,
      })
    );
    await provider.sendAndConfirm(tx);
    return kp;
  };

  /**
   * Normalizes whatever a failed `.rpc()` threw into the Anchor error code that
   * actually fired, so negative tests can assert the exact code rather than
   * "some error". Falls back to the raw message for non-Anchor failures such as
   * "account already in use".
   */
  const describeFailure = (
    e: any
  ): { code: number | null; name: string | null; raw: string } => {
    if (e && e.error && e.error.errorCode) {
      return {
        code: e.error.errorCode.number,
        name: e.error.errorCode.code,
        raw: String(e.message ?? e),
      };
    }
    const raw = String(e?.message ?? e);
    const logs: string[] = e?.logs ?? e?.transactionLogs ?? [];
    return { code: null, name: null, raw: raw + "\n" + logs.join("\n") };
  };

  /** Asserts the promise rejects, and returns the decoded failure for inspection. */
  const mustFail = async (
    p: Promise<unknown>,
    what: string
  ): Promise<{ code: number | null; name: string | null; raw: string }> => {
    let err: any = undefined;
    try {
      await p;
    } catch (e) {
      err = e;
    }
    if (err === undefined) {
      assert.fail(`${what}: expected the transaction to be rejected, but it succeeded`);
    }
    const info = describeFailure(err);
    console.log(
      `        -> rejected by: ${info.name ?? "(non-Anchor)"}${
        info.code !== null ? ` (${info.code})` : ""
      }`
    );
    return info;
  };

  // --- happy-path smoke tests (pre-existing) --------------------------------

  it("initializes config and the GT mint with a permanent delegate", async () => {
    await program.methods
      .initialize()
      .accountsPartial({
        authority,
        config: configPda,
        mint: mintPda,
        tokenProgram: TOKEN_2022_PROGRAM_ID,
      })
      .rpc();

    const config = await program.account.config.fetch(configPda);
    assert.ok(config.authority.equals(authority), "authority mismatch");
    assert.ok(config.mint.equals(mintPda), "mint mismatch");
    assert.equal(config.totalMinted.toNumber(), 0);
    assert.equal(config.totalBurned.toNumber(), 0);
    assert.equal(config.version, 1);

    const mint = await getMint(
      provider.connection,
      mintPda,
      undefined,
      TOKEN_2022_PROGRAM_ID
    );
    assert.equal(mint.decimals, 2, "GT must have 2 decimals");
    assert.ok(
      mint.mintAuthority?.equals(configPda),
      "mint authority must be the config PDA"
    );

    // The load-bearing assertion: the PermanentDelegate extension must point
    // at the config PDA, which is what makes signature-free burns possible.
    const delegate = getPermanentDelegate(mint);
    assert.ok(delegate, "PermanentDelegate extension is missing");
    assert.ok(
      delegate!.delegate.equals(configPda),
      "permanent delegate must be the config PDA"
    );
  });

  it("mints GT into a fresh citizen ATA", async () => {
    await program.methods
      .mintTokens(MINT_AMOUNT)
      .accountsPartial({
        authority,
        config: configPda,
        mint: mintPda,
        citizen,
        citizenAta,
        tokenProgram: TOKEN_2022_PROGRAM_ID,
      })
      .rpc();

    const ata = await getAccount(
      provider.connection,
      citizenAta,
      undefined,
      TOKEN_2022_PROGRAM_ID
    );
    assert.equal(ata.amount.toString(), MINT_AMOUNT.toString());

    const config = await program.account.config.fetch(configPda);
    assert.equal(config.totalMinted.toString(), MINT_AMOUNT.toString());
  });

  it("burns GT from the citizen without the citizen signing", async () => {
    await program.methods
      .burnTokens(BURN_AMOUNT)
      .accountsPartial({
        authority,
        config: configPda,
        mint: mintPda,
        citizen,
        citizenAta,
        tokenProgram: TOKEN_2022_PROGRAM_ID,
      })
      .rpc();

    const expected = MINT_AMOUNT.sub(BURN_AMOUNT);

    const ata = await getAccount(
      provider.connection,
      citizenAta,
      undefined,
      TOKEN_2022_PROGRAM_ID
    );
    assert.equal(ata.amount.toString(), expected.toString());

    const config = await program.account.config.fetch(configPda);
    assert.equal(config.totalBurned.toString(), BURN_AMOUNT.toString());
  });

  // --- initialize -----------------------------------------------------------

  describe("initialize", () => {
    it("stores the canonical bump rather than recomputing it", async () => {
      const config = await program.account.config.fetch(configPda);

      assert.ok(config.authority.equals(authority), "authority must be the deployer");
      assert.ok(config.mint.equals(mintPda), "mint must be the [b'mint'] PDA");
      assert.equal(
        config.bump,
        configBump,
        "stored bump must equal the canonical bump from findProgramAddressSync"
      );
    });

    it("cannot be run a second time", async () => {
      const info = await mustFail(
        program.methods
          .initialize()
          .accountsPartial({
            authority,
            config: configPda,
            mint: mintPda,
            tokenProgram: TOKEN_2022_PROGRAM_ID,
          })
          .rpc(),
        "second initialize"
      );

      assert.match(
        info.raw,
        /already in use/i,
        "re-initialization must be blocked by the System Program, not silently overwrite config"
      );
    });

    it("mint's PermanentDelegate resolves to the config PDA", async () => {
      const mint = await getMint(
        provider.connection,
        mintPda,
        undefined,
        TOKEN_2022_PROGRAM_ID
      );

      const delegate = getPermanentDelegate(mint);
      assert.ok(delegate, "PermanentDelegate extension must be present on the GT mint");
      assert.ok(
        delegate!.delegate.equals(configPda),
        `permanent delegate must be ${configPda.toBase58()}, got ${delegate!.delegate.toBase58()}`
      );
    });
  });

  // --- mint_tokens ----------------------------------------------------------

  describe("mint_tokens", () => {
    const freshCitizen = Keypair.generate().publicKey;
    const freshAta = ataOf(freshCitizen);
    const AMOUNT = new anchor.BN(5_000); // 50.00 GT

    it("credits the citizen ATA and increases total supply", async () => {
      const supplyBefore = await gtSupply();

      await program.methods
        .mintTokens(AMOUNT)
        .accountsPartial({
          authority,
          config: configPda,
          mint: mintPda,
          citizen: freshCitizen,
          citizenAta: freshAta,
          tokenProgram: TOKEN_2022_PROGRAM_ID,
        })
        .rpc();

      assert.equal(
        (await gtBalance(freshAta)).toString(),
        AMOUNT.toString(),
        "fresh ATA balance must equal the minted amount"
      );
      assert.equal(
        (await gtSupply()).toString(),
        (supplyBefore + BigInt(AMOUNT.toString())).toString(),
        "mint supply must grow by exactly the minted amount"
      );
    });

    it("rejects amount = 0 with InvalidAmount", async () => {
      const info = await mustFail(
        program.methods
          .mintTokens(new anchor.BN(0))
          .accountsPartial({
            authority,
            config: configPda,
            mint: mintPda,
            citizen: freshCitizen,
            citizenAta: freshAta,
            tokenProgram: TOKEN_2022_PROGRAM_ID,
          })
          .rpc(),
        "mint of zero"
      );

      assert.equal(info.code, 6003, "expected InvalidAmount (6003)");
      assert.equal(info.name, "InvalidAmount");
    });

    it("rejects an unrelated signer as authority", async () => {
      const attacker = await fundedKeypair();
      const victim = Keypair.generate().publicKey;

      const info = await mustFail(
        program.methods
          .mintTokens(new anchor.BN(1_000_000))
          .accountsPartial({
            authority: attacker.publicKey,
            config: configPda,
            mint: mintPda,
            citizen: victim,
            citizenAta: ataOf(victim),
            tokenProgram: TOKEN_2022_PROGRAM_ID,
          })
          .signers([attacker])
          .rpc(),
        "mint signed by an unrelated keypair"
      );

      assert.equal(
        info.code,
        6000,
        "has_one = authority must reject with the program's Unauthorized (6000)"
      );
      assert.equal(info.name, "Unauthorized");
    });
  });

  // --- burn_tokens ----------------------------------------------------------

  describe("burn_tokens", () => {
    const burnCitizen = Keypair.generate().publicKey;
    const burnAta = ataOf(burnCitizen);
    const SEED_AMOUNT = new anchor.BN(10_000); // 100.00 GT
    const BURN_WITHIN = new anchor.BN(4_000); //  40.00 GT

    before(async () => {
      await program.methods
        .mintTokens(SEED_AMOUNT)
        .accountsPartial({
          authority,
          config: configPda,
          mint: mintPda,
          citizen: burnCitizen,
          citizenAta: burnAta,
          tokenProgram: TOKEN_2022_PROGRAM_ID,
        })
        .rpc();
    });

    it("burns within balance, destroying supply, with no citizen signature", async () => {
      const supplyBefore = await gtSupply();

      const sig = await program.methods
        .burnTokens(BURN_WITHIN)
        .accountsPartial({
          authority,
          config: configPda,
          mint: mintPda,
          citizen: burnCitizen,
          citizenAta: burnAta,
          tokenProgram: TOKEN_2022_PROGRAM_ID,
        })
        .rpc();

      assert.equal(
        (await gtBalance(burnAta)).toString(),
        SEED_AMOUNT.sub(BURN_WITHIN).toString(),
        "100.00 GT minus a 40.00 GT burn must leave 60.00 GT"
      );
      assert.equal(
        (await gtSupply()).toString(),
        (supplyBefore - BigInt(BURN_WITHIN.toString())).toString(),
        "burn must destroy supply, not merely move tokens"
      );

      // Proof of the PermanentDelegate path: exactly one signature (the
      // backend authority / fee payer) was required. The citizen keypair was
      // never even constructed as a signer.
      await provider.connection.confirmTransaction(sig, "confirmed");
      const tx = await provider.connection.getTransaction(sig, {
        commitment: "confirmed",
        maxSupportedTransactionVersion: 0,
      });
      assert.ok(tx, "burn transaction must be retrievable");
      assert.equal(
        tx!.transaction.message.header.numRequiredSignatures,
        1,
        "burn must require exactly one signature (the backend authority)"
      );
      const signerKeys = tx!.transaction.message
        .getAccountKeys()
        .staticAccountKeys.slice(0, 1)
        .map((k) => k.toBase58());
      assert.deepEqual(
        signerKeys,
        [authority.toBase58()],
        "the only signer must be the backend authority"
      );
      assert.notInclude(
        signerKeys,
        burnCitizen.toBase58(),
        "the citizen must never appear as a signer"
      );
    });

    it("rejects a burn exceeding balance with InsufficientBalance", async () => {
      const balance = await gtBalance(burnAta);
      const tooMuch = new anchor.BN((balance + 1n).toString());

      const info = await mustFail(
        program.methods
          .burnTokens(tooMuch)
          .accountsPartial({
            authority,
            config: configPda,
            mint: mintPda,
            citizen: burnCitizen,
            citizenAta: burnAta,
            tokenProgram: TOKEN_2022_PROGRAM_ID,
          })
          .rpc(),
        "burn exceeding balance"
      );

      assert.equal(info.code, 6002, "expected InsufficientBalance (6002)");
      assert.equal(info.name, "InsufficientBalance");
    });

    it("rejects amount = 0 with InvalidAmount", async () => {
      const info = await mustFail(
        program.methods
          .burnTokens(new anchor.BN(0))
          .accountsPartial({
            authority,
            config: configPda,
            mint: mintPda,
            citizen: burnCitizen,
            citizenAta: burnAta,
            tokenProgram: TOKEN_2022_PROGRAM_ID,
          })
          .rpc(),
        "burn of zero"
      );

      assert.equal(info.code, 6003, "expected InvalidAmount (6003)");
      assert.equal(info.name, "InvalidAmount");
    });

    it("rejects an unrelated signer as authority", async () => {
      const attacker = await fundedKeypair();

      const info = await mustFail(
        program.methods
          .burnTokens(new anchor.BN(100))
          .accountsPartial({
            authority: attacker.publicKey,
            config: configPda,
            mint: mintPda,
            citizen: burnCitizen,
            citizenAta: burnAta,
            tokenProgram: TOKEN_2022_PROGRAM_ID,
          })
          .signers([attacker])
          .rpc(),
        "burn signed by an unrelated keypair"
      );

      assert.equal(
        info.code,
        6000,
        "has_one = authority must reject with the program's Unauthorized (6000)"
      );
      assert.equal(info.name, "Unauthorized");

      // The victim's balance must be untouched.
      assert.equal(
        (await gtBalance(burnAta)).toString(),
        SEED_AMOUNT.sub(BURN_WITHIN).toString(),
        "a rejected burn must not move the victim's balance"
      );
    });
  });

  // --- wrong-mint ATA -------------------------------------------------------

  describe("wrong-mint ATA", () => {
    let foreignMint: PublicKey;
    let foreignAta: PublicKey;
    const wrongMintCitizen = Keypair.generate().publicKey;

    before(async () => {
      const payer = await fundedKeypair();

      // A Token-2022 mint that has nothing to do with this program.
      foreignMint = await createMint(
        provider.connection,
        payer,
        payer.publicKey,
        null,
        2,
        Keypair.generate(),
        undefined,
        TOKEN_2022_PROGRAM_ID
      );

      foreignAta = await createAssociatedTokenAccount(
        provider.connection,
        payer,
        foreignMint,
        wrongMintCitizen,
        undefined,
        TOKEN_2022_PROGRAM_ID,
        ASSOCIATED_TOKEN_PROGRAM_ID
      );
    });

    it("rejects an ATA of a foreign mint on mint_tokens", async () => {
      const info = await mustFail(
        program.methods
          .mintTokens(new anchor.BN(1_000))
          .accountsPartial({
            authority,
            config: configPda,
            mint: mintPda,
            citizen: wrongMintCitizen,
            citizenAta: foreignAta,
            tokenProgram: TOKEN_2022_PROGRAM_ID,
          })
          .rpc(),
        "mint into a foreign-mint ATA"
      );

      // On the `init_if_needed` path the already-exists branch checks
      // `citizen_ata.mint == mint` before the ATA-address derivation, so
      // ConstraintTokenMint is what fires here rather than ConstraintAssociated.
      assert.equal(info.code, 2014, "expected ConstraintTokenMint (2014)");
      assert.equal(info.name, "ConstraintTokenMint");
    });

    it("rejects an ATA of a foreign mint on burn_tokens", async () => {
      const info = await mustFail(
        program.methods
          .burnTokens(new anchor.BN(1))
          .accountsPartial({
            authority,
            config: configPda,
            mint: mintPda,
            citizen: wrongMintCitizen,
            citizenAta: foreignAta,
            tokenProgram: TOKEN_2022_PROGRAM_ID,
          })
          .rpc(),
        "burn from a foreign-mint ATA"
      );

      // Without `init_if_needed` the ATA-address derivation check runs first,
      // so the same input is rejected one constraint earlier than on
      // `mint_tokens`. Either way the account never reaches the handler.
      assert.equal(info.code, 2009, "expected ConstraintAssociated (2009)");
      assert.equal(info.name, "ConstraintAssociated");
    });

    it("rejects a foreign mint account outright with InvalidMint", async () => {
      const info = await mustFail(
        program.methods
          .burnTokens(new anchor.BN(1))
          .accountsPartial({
            authority,
            config: configPda,
            mint: foreignMint,
            citizen: wrongMintCitizen,
            citizenAta: foreignAta,
            tokenProgram: TOKEN_2022_PROGRAM_ID,
          })
          .rpc(),
        "burn with a foreign mint account"
      );

      assert.equal(info.code, 6001, "expected InvalidMint (6001)");
      assert.equal(info.name, "InvalidMint");
    });
  });

  // --- compute unit profile -------------------------------------------------

  describe("compute unit profile", () => {
    const results: Array<{ label: string; total: number; own: number; cpi: string[] }> =
      [];

    const pid = program.programId.toBase58();

    /**
     * Splits a transaction's compute usage into the whole-transaction figure
     * (`meta.computeUnitsConsumed`), this program's own top-level consumption,
     * and each inner CPI's consumption, so a regression can be attributed to
     * the handler itself rather than to a CPI or to ATA creation.
     */
    const cuFor = async (
      sig: string
    ): Promise<{ total: number; own: number; cpi: string[] }> => {
      await provider.connection.confirmTransaction(sig, "confirmed");
      const tx = await provider.connection.getTransaction(sig, {
        commitment: "confirmed",
        maxSupportedTransactionVersion: 0,
      });
      const logs = tx?.meta?.logMessages ?? [];

      let own = 0;
      const cpi: string[] = [];
      for (const line of logs) {
        const m = line.match(/^Program (\S+) consumed (\d+) of (\d+) compute units$/);
        if (!m) continue;
        if (m[1] === pid) {
          own = parseInt(m[2], 10);
        } else {
          cpi.push(`${m[1].slice(0, 8)}.. ${m[2]} CU`);
        }
      }

      const total = tx?.meta?.computeUnitsConsumed ?? own;
      if (own === 0) throw new Error(`could not determine CU for ${sig}`);
      return { total, own, cpi };
    };

    /** Canonical ATA bump for a citizen — the count of `create_program_address`
     *  probes the runtime must burn is `256 - bump`, at 1500 CU each. */
    const ataBumpOf = (owner: PublicKey): number =>
      PublicKey.findProgramAddressSync(
        [owner.toBuffer(), TOKEN_2022_PROGRAM_ID.toBuffer(), mintPda.toBuffer()],
        ASSOCIATED_TOKEN_PROGRAM_ID
      )[1];

    /**
     * A citizen pubkey derived from a fixed seed, so CU figures are reproducible
     * run to run. Random citizens make the numbers jitter by 1500 CU per bump
     * probe, which is the very effect the last profiling case measures.
     */
    const seededCitizen = (fill: number): PublicKey =>
      Keypair.fromSeed(Uint8Array.from(new Array(32).fill(fill))).publicKey;

    /** First seeded citizen whose GT ATA has the given canonical bump. */
    const citizenWithAtaBump = (bump: number): PublicKey => {
      for (let fill = 1; fill < 256; fill++) {
        const c = seededCitizen(fill);
        if (ataBumpOf(c) === bump) return c;
      }
      throw new Error(`no seeded citizen found with ATA bump ${bump}`);
    };

    // Best case: ATA bump 255, a single create_program_address probe.
    const profileCitizen = citizenWithAtaBump(255);
    const profileAta = ataOf(profileCitizen);

    it("mint_tokens - cold path (ATA created via init_if_needed)", async () => {
      const sig = await program.methods
        .mintTokens(new anchor.BN(10_000))
        .accountsPartial({
          authority,
          config: configPda,
          mint: mintPda,
          citizen: profileCitizen,
          citizenAta: profileAta,
          tokenProgram: TOKEN_2022_PROGRAM_ID,
        })
        .rpc();

      results.push({
        label: "mint_tokens (cold / ATA created)",
        ...(await cuFor(sig)),
      });
    });

    it("mint_tokens - warm path (ATA already exists)", async () => {
      const sig = await program.methods
        .mintTokens(new anchor.BN(2_500))
        .accountsPartial({
          authority,
          config: configPda,
          mint: mintPda,
          citizen: profileCitizen,
          citizenAta: profileAta,
          tokenProgram: TOKEN_2022_PROGRAM_ID,
        })
        .rpc();

      results.push({
        label: "mint_tokens (warm / ATA exists)",
        ...(await cuFor(sig)),
      });
    });

    it("burn_tokens", async () => {
      const sig = await program.methods
        .burnTokens(new anchor.BN(1_000))
        .accountsPartial({
          authority,
          config: configPda,
          mint: mintPda,
          citizen: profileCitizen,
          citizenAta: profileAta,
          tokenProgram: TOKEN_2022_PROGRAM_ID,
        })
        .rpc();

      results.push({ label: "burn_tokens", ...(await cuFor(sig)) });
    });

    it("mint_tokens - warm path for a citizen with a lower ATA bump", async () => {
      // Same instruction, same amount; only the citizen's canonical ATA bump
      // differs. Any delta here is pure `find_program_address` probing, at
      // 1500 CU per probe, and is the reason CU is not constant per citizen.
      const lowBump = 253;
      const citizenLowBump = citizenWithAtaBump(lowBump);
      const ataLowBump = ataOf(citizenLowBump);

      // Cold call first, only to create the ATA; not measured.
      await program.methods
        .mintTokens(new anchor.BN(10_000))
        .accountsPartial({
          authority,
          config: configPda,
          mint: mintPda,
          citizen: citizenLowBump,
          citizenAta: ataLowBump,
          tokenProgram: TOKEN_2022_PROGRAM_ID,
        })
        .rpc();

      const sig = await program.methods
        .mintTokens(new anchor.BN(2_500))
        .accountsPartial({
          authority,
          config: configPda,
          mint: mintPda,
          citizen: citizenLowBump,
          citizenAta: ataLowBump,
          tokenProgram: TOKEN_2022_PROGRAM_ID,
        })
        .rpc();

      results.push({
        label: `mint_tokens (warm / ATA bump ${lowBump})`,
        ...(await cuFor(sig)),
      });
    });

    after(() => {
      console.log("\n      Compute units");
      console.log(
        `        ${"instruction path".padEnd(34)} ${"tx total".padStart(9)} ${"program".padStart(9)}   inner CPIs`
      );
      for (const r of results) {
        console.log(
          `        ${r.label.padEnd(34)} ${String(r.total).padStart(9)} ${String(
            r.own
          ).padStart(9)}   ${r.cpi.join(", ") || "-"}`
        );
      }
      console.log("");
    });
  });
});
