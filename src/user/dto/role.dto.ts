import { Types } from 'mongoose';
import { Role, RoleCode } from '../../auth/schemas/role.schema';
import { IsNotEmpty } from 'class-validator';
import { IsMongoIdObject } from '../../common/mongo.validation';

export class RoleDto {
  @IsMongoIdObject()
  readonly _id: Types.ObjectId;

  @IsNotEmpty()
  readonly code: RoleCode;

  constructor(role: Role) {
    this._id = role._id;
    this.code = role.code;
  }
}
