// sign-promotional-offer
//
// Signs a compact JWS for StoreKit 2's
// `Product.PurchaseOption.promotionalOffer(_:compactJWS:)` -- the current
// (post iOS 17.4) way to apply an App Store subscription promotional-offer
// discount at purchase time. Exists because SuperwallKit 4.16.1's own
// purchase path (Superwall.shared.purchase(product:) -> SomaPurchaseController)
// never inserts a `.promotionalOffer` PurchaseOption -- confirmed against
// the pinned SDK's ProductPurchaserSK2.swift -- so WinBackOfferManager
// calls this directly and performs the StoreKit 2 purchase itself for
// just the exit-offer screen, bypassing Superwall's purchase() for that
// one call only.
//
// Body: { productId: string, offerId: string, transactionId?: string }
// Response: { compactJWS: string }
//
// Header/payload shape verified against Apple's own official, open-source
// PromotionalOfferV2SignatureCreator (Swift): see
// https://github.com/apple/app-store-server-library-swift/blob/main/Sources/AppStoreServerLibrary/JWSSignatureCreator.swift
// -- developer.apple.com's own promotional-offer JWS reference pages are
// JS-rendered and didn't yield the exact claim set, so this was read
// straight from Apple's reference implementation instead of guessed.
// Still worth one real sandbox purchase (Phone/TestFlight, NOT the
// simulator -- Soma.storekit can't fixture a signed promotional offer)
// before this ever signs a live offer.
//
// If a future Apple update deprecates/replaces PromotionalOfferV2SignatureCreator,
// re-derive this from whatever supersedes it rather than trusting this
// comment indefinitely.

import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/clients.ts";

const BUNDLE_ID = "com.skollnitzer.soma";

// App Store Connect -> Users and Access -> Integrations -> In-App Purchase
// Key. PROMOTIONAL_OFFER_KEY_ID is that key's Key ID; PROMOTIONAL_OFFER_KEY_P8
// is the full contents of the downloaded .p8 file (PEM, PKCS8 EC private
// key); PROMOTIONAL_OFFER_ISSUER_ID is the Issuer ID shown at the top of
// that same Keys page (a UUID-looking value, shared across all your ASC
// API keys -- NOT the key ID). Set all three via `supabase secrets set`,
// never commit the .p8 itself. Apple lets you download a given IAP key's
// .p8 file exactly ONCE -- store it in a password manager/secrets vault
// immediately, since losing it means generating a new key (and re-running
// `secrets set`) rather than re-downloading.
const KEY_ID = Deno.env.get("PROMOTIONAL_OFFER_KEY_ID");
const ISSUER_ID = Deno.env.get("PROMOTIONAL_OFFER_ISSUER_ID");
const PRIVATE_KEY_PEM = Deno.env.get("PROMOTIONAL_OFFER_KEY_P8");

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importSigningKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  try {
    if (!KEY_ID || !ISSUER_ID || !PRIVATE_KEY_PEM) {
      return jsonResponse({ error: "Promotional offer signing key not configured" }, 500);
    }

    const userId = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const productId: string | undefined = body.productId;
    const offerId: string | undefined = body.offerId;
    // Optional but Apple-recommended -- the customer's appTransactionID,
    // sent even for someone who's never purchased anything (WinBackOfferManager
    // reads it from StoreKit 2's AppTransaction.shared). Omit rather than
    // guess if the client couldn't obtain one.
    const transactionId: string | undefined = body.transactionId;
    if (!productId || !offerId) {
      return jsonResponse({ error: "missing 'productId' or 'offerId'" }, 400);
    }
    void userId; // not itself part of the Apple payload -- see comment below

    // Belt-and-suspenders: only ever sign for Soma's own two products,
    // never whatever a client happens to send.
    const allowedProductIds = new Set([
      "com.skollnitzer.soma.premium.monthly",
      "com.skollnitzer.soma.premium.annual",
    ]);
    if (!allowedProductIds.has(productId)) {
      return jsonResponse({ error: "unknown productId" }, 400);
    }

    const key = await importSigningKey(PRIVATE_KEY_PEM);

    const header = { alg: "ES256", kid: KEY_ID, typ: "JWT" };
    // Claim set matches PromotionalOfferV2Payload exactly -- iss is the
    // ASC *Issuer ID*, not the key ID; offerIdentifier (not offerId) is
    // the wire name Apple expects; there is no exp/applicationUsername
    // claim in the real payload, unlike the deprecated v1 scheme.
    const payload: Record<string, unknown> = {
      nonce: crypto.randomUUID(),
      iss: ISSUER_ID,
      bid: BUNDLE_ID,
      aud: "promotional-offer",
      iat: Math.floor(Date.now() / 1000),
      productId,
      offerIdentifier: offerId,
    };
    if (transactionId) {
      payload.transactionId = transactionId;
    }

    const encodedHeader = base64url(new TextEncoder().encode(JSON.stringify(header)));
    const encodedPayload = base64url(new TextEncoder().encode(JSON.stringify(payload)));
    const signingInput = `${encodedHeader}.${encodedPayload}`;

    // WebCrypto's ECDSA signature output is already raw (r || s), which is
    // what JWS ES256 expects -- no DER conversion needed.
    const signatureBytes = new Uint8Array(
      await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        new TextEncoder().encode(signingInput),
      ),
    );

    const compactJWS = `${signingInput}.${base64url(signatureBytes)}`;
    return jsonResponse({ compactJWS });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status = msg === "unauthorized" ? 401 : 500;
    return jsonResponse({ error: msg }, status);
  }
});
