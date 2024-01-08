import { MaxLength } from 'class-validator';

export class TokenRefreshDto {
  @MaxLength(500)
  refreshToken: string;
}
