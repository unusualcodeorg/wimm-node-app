import { Types } from 'mongoose';
import { User } from '../schemas/user.schema';
import { IsNotEmpty, IsOptional, IsUrl } from 'class-validator';
import { IsMongoIdObject } from '../../common/mongo.validation';
import { copy } from '../../common/copier';

export class UserInfoDto {
  @IsMongoIdObject()
  readonly _id: Types.ObjectId;

  @IsNotEmpty()
  @IsOptional()
  readonly name?: string;

  @IsUrl({ require_tld: false })
  @IsOptional()
  readonly profilePicUrl?: string;

  constructor(user: User) {
    Object.assign(this, copy(user, ['_id', 'name', 'profilePicUrl']));
  }
}
