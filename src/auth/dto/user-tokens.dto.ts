import { IsNotEmpty } from 'class-validator';

export class UserTokensDto {
  @IsNotEmpty()
  readonly accessToken: string;

  @IsNotEmpty()
  readonly refreshToken: string;

  constructor(tokens: UserTokensDto) {
    Object.assign(this, tokens);
  }
}
