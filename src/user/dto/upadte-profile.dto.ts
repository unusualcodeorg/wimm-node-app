import { IsOptional, IsUrl, MaxLength } from 'class-validator';

export class UpdateProfileDto {
  @IsOptional()
  @MaxLength(200)
  readonly name?: string;

  @IsOptional()
  @IsUrl({ require_tld: false })
  @MaxLength(500)
  readonly profilePicUrl?: string;

  @IsOptional()
  @MaxLength(2000)
  readonly firebaseToken?: string;

  @IsOptional()
  @MaxLength(500)
  readonly tagline?: string;
}
