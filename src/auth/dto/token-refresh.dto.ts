import { MaxLength } from 'class-validator';

export class TokenRefreshDto {
  @MaxLength(1000)
  refreshToken: string;
}
