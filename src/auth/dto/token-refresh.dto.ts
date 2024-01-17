import { MaxLength } from 'class-validator';

export class TokenRefreshDto {
  @MaxLength(2000)
  refreshToken: string;
}
