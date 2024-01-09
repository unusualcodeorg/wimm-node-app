import { UserEntity } from '../../user/entities/user.entity';
import { User } from '../../user/schemas/user.schema';
import { IsNotEmptyObject, ValidateNested } from 'class-validator';
import { TokensEntity } from './tokens.entity';

export class SignInEntity {
  @ValidateNested()
  @IsNotEmptyObject()
  readonly user: UserEntity;

  @ValidateNested()
  @IsNotEmptyObject()
  readonly tokens: TokensEntity;

  constructor(user: User, tokens: TokensEntity) {
    this.user = new UserEntity(user);
    this.tokens = tokens;
  }
}
