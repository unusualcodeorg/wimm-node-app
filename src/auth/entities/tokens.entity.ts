import { IsNotEmpty } from 'class-validator';

export class TokensEntity {
  @IsNotEmpty()
  readonly accessToken: string;

  @IsNotEmpty()
  readonly refreshToken: string;

  constructor(tokens: TokensEntity) {
    Object.assign(this, tokens);
  }
}
