import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { User } from './schemas/user.schema';

@Injectable()
export class UserService {
  constructor(
    @InjectModel(User.name) private readonly userModel: Model<User>,
  ) {}

  readonly USER_CRITICAL_DETAIL =
    '+email +password +roles +googleId +facebookId';

  async findUserById(id: Types.ObjectId) {
    return this.userModel
      .findOne({ _id: id, status: true })
      .select(this.USER_CRITICAL_DETAIL)
      .populate({
        path: 'roles',
        match: { status: true },
      })
      .lean()
      .exec();
  }
}
