import { IsEmail, MaxLength, MinLength } from 'class-validator';

export class SignInBasicDto {
  @IsEmail()
  readonly email: string;

  @MinLength(6)
  @MaxLength(100)
  readonly password: string;
}
