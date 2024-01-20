import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { User } from './schemas/user.schema';
import { UpdateProfileDto } from './dto/upadte-profile.dto';
import { UserDto } from './dto/user.dto';

@Injectable()
export class UserService {
  constructor(
    @InjectModel(User.name) private readonly userModel: Model<User>,
  ) {}

  readonly USER_CRITICAL_DETAIL =
    '+email +password +roles +googleId +facebookId';

  async create(user: Omit<User, '_id' | 'status'>): Promise<User> {
    const created = await this.userModel.create(user);
    return { ...created.toObject(), roles: user.roles };
  }

  async updateProfile(user: User, updateProfileDto: UpdateProfileDto) {
    const something =
      updateProfileDto.name ||
      updateProfileDto.profilePicUrl ||
      updateProfileDto.tagline ||
      updateProfileDto.firebaseToken;

    if (!something) return new UserDto(user);

    const updated = await this.updateUserInfo({
      _id: user._id,
      ...updateProfileDto,
    });

    if (!updated) throw new InternalServerErrorException();

    return new UserDto(updated);
  }

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

  async findByEmail(email: string) {
    return this.userModel
      .findOne({ email: email })
      .select(this.USER_CRITICAL_DETAIL)
      .populate({
        path: 'roles',
        match: { status: true },
      })
      .lean()
      .exec();
  }

  async findPrivateProfile(user: User) {
    return this.userModel
      .findOne({ _id: user._id, status: true })
      .select('+email')
      .populate({
        path: 'roles',
        match: { status: true },
        select: { code: 1 },
      })
      .lean()
      .exec();
  }

  async updateUserInfo(user: Partial<User>) {
    return this.userModel
      .findByIdAndUpdate({ _id: user._id, status: true }, { $set: user })
      .select('+email')
      .populate({
        path: 'roles',
        match: { status: true },
        select: { code: 1 },
      })
      .lean()
      .exec();
  }

  async delete(user: User) {
    return this.userModel.findByIdAndDelete(user._id);
  }

  async deactivate(user: User): Promise<User | null> {
    return this.userModel.findByIdAndUpdate(user._id, { status: false });
  }
}
