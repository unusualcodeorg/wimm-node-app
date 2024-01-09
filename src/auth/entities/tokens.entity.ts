export class TokensEntity {
  accessToken: string;
  refreshToken: string;

  constructor(tokens: TokensEntity) {
    Object.assign(this, tokens);
  }
}
