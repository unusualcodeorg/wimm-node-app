import { Types } from 'mongoose';
import { User } from '../../user/schemas/user.schema';
import { IsEmail, IsNotEmpty, IsOptional, IsUrl } from 'class-validator';
import { IsMongoIdObject } from '../../core/validations/mongo.validation';

export class UserEntity {
  @IsMongoIdObject()
  readonly _id: Types.ObjectId;

  @IsEmail()
  readonly email: string;

  @IsNotEmpty()
  @IsOptional()
  readonly name?: string;

  @IsUrl()
  @IsOptional()
  readonly profilePicUrl?: string;

  constructor(user: User) {
    this._id = user._id;
    this.name = user.name;
    this.email = user.email;
    this.profilePicUrl = user.profilePicUrl;
  }
}
