import { UserEntity } from './user.entity';
import { RoleEntity } from './role.entity';
import { TokensEntity } from './tokens.entity';
import { User } from '../../user/schemas/user.schema';
import { IsArray, IsNotEmptyObject, ValidateNested } from 'class-validator';

export class SignInEntity {
  @ValidateNested()
  @IsNotEmptyObject()
  readonly user: UserEntity;

  @ValidateNested()
  @IsArray()
  readonly roles: RoleEntity[];

  @ValidateNested()
  @IsNotEmptyObject()
  readonly tokens: TokensEntity;

  constructor(user: User, tokens: TokensEntity) {
    this.user = new UserEntity(user);
    this.roles = user.roles.map((role) => new RoleEntity(role));
    this.tokens = tokens;
  }
}
