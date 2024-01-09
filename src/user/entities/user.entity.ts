import { Types } from 'mongoose';
import { User } from '../../user/schemas/user.schema';
import {
  IsArray,
  IsEmail,
  IsNotEmpty,
  IsOptional,
  IsUrl,
  ValidateNested,
} from 'class-validator';
import { IsMongoIdObject } from '../../core/validations/mongo.validation';
import { RoleEntity } from './role.entity';

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

  @IsNotEmpty()
  @IsOptional()
  readonly tagline?: string;

  @ValidateNested()
  @IsArray()
  readonly roles: RoleEntity[];

  constructor(user: User) {
    this._id = user._id;
    this.name = user.name;
    this.email = user.email;
    this.profilePicUrl = user.profilePicUrl;
    this.tagline = user.tagline;
    this.roles = user.roles.map((role) => new RoleEntity(role));
  }
}
