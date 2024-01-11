import { UserDto } from '../../user/dto/user.dto';
import { User } from '../../user/schemas/user.schema';
import { IsNotEmptyObject, ValidateNested } from 'class-validator';
import { UserTokensDto } from './user-tokens.dto';

export class UserAuthDto {
  @ValidateNested()
  @IsNotEmptyObject()
  readonly user: UserDto;

  @ValidateNested()
  @IsNotEmptyObject()
  readonly tokens: UserTokensDto;

  constructor(user: User, tokens: UserTokensDto) {
    this.user = new UserDto(user);
    this.tokens = tokens;
  }
}
