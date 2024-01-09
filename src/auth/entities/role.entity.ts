import { Types } from 'mongoose';
import { Role } from '../schemas/role.schema';

export class RoleEntity {
  _id: Types.ObjectId;
  code: string;

  constructor(role: Role) {
    this._id = role._id;
    this.code = role.code;
  }
}
