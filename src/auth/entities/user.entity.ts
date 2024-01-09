import { Types } from 'mongoose';
import { User } from '../../user/schemas/user.schema';

export class UserEntity {
  _id: Types.ObjectId;
  email: string;
  name?: string;
  profilePicUrl?: string;

  constructor(user: User) {
    this._id = user._id;
    this.name = user.name;
    this.email = user.email;
    this.profilePicUrl = user.profilePicUrl;
  }
}
