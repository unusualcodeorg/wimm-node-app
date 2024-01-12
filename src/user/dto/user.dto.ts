import { Types } from 'mongoose';
import { User } from '../schemas/user.schema';
import {
  IsArray,
  IsEmail,
  IsNotEmpty,
  IsOptional,
  IsUrl,
  ValidateNested,
} from 'class-validator';
import { IsMongoIdObject } from '../../common/mongo.validation';
import { RoleDto } from './role.dto';

export class UserDto {
  @IsMongoIdObject()
  readonly _id: Types.ObjectId;

  @IsEmail()
  readonly email: string;

  @IsNotEmpty()
  @IsOptional()
  readonly name?: string;

  @IsUrl({ require_tld: false })
  @IsOptional()
  readonly profilePicUrl?: string;

  @IsNotEmpty()
  @IsOptional()
  readonly tagline?: string;

  @ValidateNested()
  @IsArray()
  readonly roles: RoleDto[];

  constructor(user: User) {
    this._id = user._id;
    this.name = user.name;
    this.email = user.email;
    this.profilePicUrl = user.profilePicUrl;
    this.tagline = user.tagline;
    this.roles = user.roles.map((role) => new RoleDto(role));
  }
}
