import {
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
} from "@apple/app-store-server-library";
import { createHash } from "node:crypto";
import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "jose";
import type { ServiceConfig } from "./config.js";

const appleJWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

export interface VerifiedTransaction {
  transactionID: string;
  originalTransactionID: string;
  productID: string;
  appAccountToken: string | null;
  environment: "Sandbox" | "Production";
  purchaseDate: number;
  revocationDate: number | null;
  signedDate: number;
  signedTransactionInfo: string;
}

export class AppleGateway {
  private readonly productionVerifier: SignedDataVerifier;
  private readonly sandboxVerifier: SignedDataVerifier;
  private readonly productionClient: AppStoreServerAPIClient;
  private readonly sandboxClient: AppStoreServerAPIClient;

  constructor(private readonly config: ServiceConfig) {
    this.productionVerifier = new SignedDataVerifier(
      config.appleRootCAs,
      true,
      Environment.PRODUCTION,
      config.appleBundleID,
      config.appleAppID,
    );
    this.sandboxVerifier = new SignedDataVerifier(
      config.appleRootCAs,
      true,
      Environment.SANDBOX,
      config.appleBundleID,
      undefined,
    );
    this.productionClient = new AppStoreServerAPIClient(
      config.appleIAPPrivateKey,
      config.appleIAPKeyID,
      config.appleIAPIssuerID,
      config.appleBundleID,
      Environment.PRODUCTION,
    );
    this.sandboxClient = new AppStoreServerAPIClient(
      config.appleIAPPrivateKey,
      config.appleIAPKeyID,
      config.appleIAPIssuerID,
      config.appleBundleID,
      Environment.SANDBOX,
    );
  }

  async verifyDeviceTransaction(signedTransactionInfo: string): Promise<VerifiedTransaction> {
    const firstPass = await this.verifyTransactionInEitherEnvironment(signedTransactionInfo);
    const client = firstPass.environment === "Production"
      ? this.productionClient
      : this.sandboxClient;
    const response = await client.getTransactionInfo(firstPass.transactionID);
    if (!response.signedTransactionInfo) {
      throw new Error("apple_transaction_missing");
    }
    const serverTransaction = await this.verifyTransaction(
      response.signedTransactionInfo,
      firstPass.environment,
    );
    if (serverTransaction.transactionID !== firstPass.transactionID) {
      throw new Error("apple_transaction_mismatch");
    }
    return serverTransaction;
  }

  async verifyNotification(signedPayload: string): Promise<{
    notificationUUID: string;
    notificationType: string;
    signedDate: number;
    transaction: VerifiedTransaction | null;
    environment: "Sandbox" | "Production";
  }> {
    for (const environment of ["Production", "Sandbox"] as const) {
      try {
        const verifier = environment === "Production"
          ? this.productionVerifier
          : this.sandboxVerifier;
        const decoded = await verifier.verifyAndDecodeNotification(signedPayload);
        if (!decoded.notificationUUID || !decoded.notificationType || !decoded.signedDate) {
          throw new Error("invalid_apple_notification");
        }
        const signedTransaction = decoded.data?.signedTransactionInfo;
        return {
          notificationUUID: decoded.notificationUUID,
          notificationType: decoded.notificationType,
          signedDate: decoded.signedDate,
          transaction: signedTransaction
            ? await this.verifyTransaction(signedTransaction, environment)
            : null,
          environment,
        };
      } catch (error) {
        if (environment === "Sandbox") throw error;
      }
    }
    throw new Error("invalid_apple_notification");
  }

  private async verifyTransactionInEitherEnvironment(
    signedTransactionInfo: string,
  ): Promise<VerifiedTransaction> {
    try {
      return await this.verifyTransaction(signedTransactionInfo, "Production");
    } catch {
      return this.verifyTransaction(signedTransactionInfo, "Sandbox");
    }
  }

  private async verifyTransaction(
    signedTransactionInfo: string,
    environment: "Sandbox" | "Production",
  ): Promise<VerifiedTransaction> {
    const verifier = environment === "Production"
      ? this.productionVerifier
      : this.sandboxVerifier;
    const decoded = await verifier.verifyAndDecodeTransaction(signedTransactionInfo);
    if (!decoded.transactionId || !decoded.originalTransactionId || !decoded.productId
        || !decoded.purchaseDate || !decoded.signedDate) {
      throw new Error("invalid_apple_transaction");
    }
    return {
      transactionID: decoded.transactionId,
      originalTransactionID: decoded.originalTransactionId,
      productID: decoded.productId,
      appAccountToken: decoded.appAccountToken ?? null,
      environment,
      purchaseDate: decoded.purchaseDate,
      revocationDate: decoded.revocationDate ?? null,
      signedDate: decoded.signedDate,
      signedTransactionInfo,
    };
  }

  async verifyAppleIdentity(
    identityToken: string,
    rawNonce: string,
  ): Promise<{ subject: string }> {
    const expectedNonce = createHash("sha256").update(rawNonce).digest("hex");
    const result = await jwtVerify(identityToken, appleJWKS, {
      issuer: "https://appleid.apple.com",
      audience: this.config.appleSignInClientID,
    });
    if (!result.payload.sub || result.payload.nonce !== expectedNonce) {
      throw new Error("invalid_apple_identity");
    }
    return { subject: result.payload.sub };
  }

  async revokeAuthorizationCode(authorizationCode: string, expectedSubject: string): Promise<boolean> {
    try {
      const clientSecret = await this.makeSignInClientSecret();
      const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: this.config.appleSignInClientID,
          client_secret: clientSecret,
          code: authorizationCode,
          grant_type: "authorization_code",
        }),
      });
      if (!tokenResponse.ok) return false;
      const tokenBody = await tokenResponse.json() as { refresh_token?: string; id_token?: string };
      if (!tokenBody.refresh_token || !tokenBody.id_token) return false;
      const exchangedIdentity = await jwtVerify(tokenBody.id_token, appleJWKS, {
        issuer: "https://appleid.apple.com",
        audience: this.config.appleSignInClientID,
      });
      if (exchangedIdentity.payload.sub !== expectedSubject) return false;

      const revokeResponse = await fetch("https://appleid.apple.com/auth/revoke", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: this.config.appleSignInClientID,
          client_secret: clientSecret,
          token: tokenBody.refresh_token,
          token_type_hint: "refresh_token",
        }),
      });
      return revokeResponse.ok;
    } catch {
      return false;
    }
  }

  private async makeSignInClientSecret(): Promise<string> {
    const key = await importPKCS8(this.config.appleSignInPrivateKey, "ES256");
    const now = Math.floor(Date.now() / 1_000);
    return new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: this.config.appleSignInKeyID })
      .setIssuer(this.config.appleSignInTeamID)
      .setSubject(this.config.appleSignInClientID)
      .setAudience("https://appleid.apple.com")
      .setIssuedAt(now)
      .setExpirationTime(now + 300)
      .sign(key);
  }
}

export function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
