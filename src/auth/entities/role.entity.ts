import { Types } from 'mongoose';
import { Role, RoleCode } from '../schemas/role.schema';
import { IsNotEmpty } from 'class-validator';
import { IsMongoIdObject } from '../../core/validations/mongo.validation';

export class RoleEntity {
  @IsMongoIdObject()
  readonly _id: Types.ObjectId;

  @IsNotEmpty()
  readonly code: RoleCode;

  constructor(role: Role) {
    this._id = role._id;
    this.code = role.code;
  }
}
