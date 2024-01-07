export class TokenPayload {
  readonly aud: string;
  readonly sub: string;
  readonly iss: string;
  readonly iat: number;
  readonly exp: number;
  readonly prm: string;

  constructor(
    issuer: string,
    audience: string,
    subject: string,
    param: string,
    validity: number,
  ) {
    this.iss = issuer;
    this.aud = audience;
    this.sub = subject;
    this.iat = Math.floor(Date.now() / 1000);
    this.exp = this.iat + validity;
    this.prm = param;
  }
}
