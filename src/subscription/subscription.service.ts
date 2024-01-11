import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Subscription } from './schemas/subscription.schema';
import { User } from '../user/schemas/user.schema';

@Injectable()
export class SubscriptionService {
  constructor(
    @InjectModel(Subscription.name)
    private readonly subscriptionModel: Model<Subscription>,
  ) {}

  async findById(id: Types.ObjectId): Promise<Subscription | null> {
    return this.subscriptionModel
      .findOne({ _id: id, status: true })
      .populate('topics')
      .populate('mentors')
      .lean()
      .exec();
  }

  async create(subscription: Subscription): Promise<Subscription | null> {
    const created = await this.subscriptionModel.create(subscription);
    return created.toObject();
  }

  async update(subscription: Subscription): Promise<Subscription | null> {
    return this.subscriptionModel
      .findByIdAndUpdate(subscription._id, subscription, {
        new: true,
      })
      .lean()
      .exec();
  }

  async findSubscriptionForUser(user: User): Promise<Subscription | null> {
    return this.subscriptionModel
      .findOne({ user: user, status: true })
      .lean()
      .exec();
  }

  async findSubscriptionForUserPopulated(
    user: User,
  ): Promise<Subscription | null> {
    return this.subscriptionModel
      .findOne({ user: user, status: true })
      .populate({
        path: 'mentors',
        match: { status: true },
        select: 'name thumbnail occupation title coverImgUrl',
      })
      .populate({
        path: 'topics',
        match: { status: true },
        select: 'name thumbnail title coverImgUrl',
      })
      .lean()
      .exec();
  }

  async findSubscribedMentors(user: User): Promise<Subscription | null> {
    return this.subscriptionModel
      .findOne({ user: user, status: true })
      .select('-status -topics -user')
      .populate({
        path: 'mentors',
        match: { status: true },
        select: 'name thumbnail occupation title coverImgUrl',
      })
      .lean()
      .exec();
  }

  async findSubscribedTopics(user: User): Promise<Subscription | null> {
    return this.subscriptionModel
      .findOne({ user: user, status: true })
      .select('-status -mentors -user')
      .populate({
        path: 'topics',
        match: { status: true },
        select: 'name thumbnail title coverImgUrl',
      })
      .lean()
      .exec();
  }

  async mentorSubscriptionExists(
    user: User,
    mentorId: Types.ObjectId,
  ): Promise<boolean> {
    const subscription = await this.subscriptionModel.exists({
      user: user,
      mentors: mentorId,
      status: true,
    });
    return subscription !== null && subscription !== undefined;
  }

  async topicSubscriptionExists(
    user: User,
    topicId: Types.ObjectId,
  ): Promise<boolean> {
    const subscription = await this.subscriptionModel.exists({
      user: user,
      topics: topicId,
      status: true,
    });
    return subscription !== null && subscription !== undefined;
  }
}
