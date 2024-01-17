import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Subscription } from './schemas/subscription.schema';
import { User } from '../user/schemas/user.schema';
import { MentorService } from '../mentor/mentor.service';
import { TopicService } from '../topic/topic.service';
import { SubscriptionDto } from './dto/subscription.dto';
import { PaginationDto } from '../common/pagination.dto';
import { MentorSubscriptionDto } from './dto/mentor-subscription.dto';
import { TopicSubscriptionDto } from './dto/topic-subscription.dto';

@Injectable()
export class SubscriptionService {
  constructor(
    @InjectModel(Subscription.name)
    private readonly subscriptionModel: Model<Subscription>,
    private readonly mentorService: MentorService,
    private readonly topicService: TopicService,
  ) {}

  async processSubscription(
    user: User,
    subscriptionDto: SubscriptionDto,
    mode: 'SUBSCRIBE' | 'UNSUBSCRIBE',
  ) {
    let subscription = await this.findSubscriptionForUser(user);
    if (!subscription) {
      subscription = await this.create({
        user: user,
        topics: [],
        mentors: [],
      });
    }

    if (!subscription) throw new InternalServerErrorException();

    const mentorIds = subscriptionDto.mentorIds;
    const topicIds = subscriptionDto.topicIds;

    let modified = false;

    if (mentorIds && mentorIds.length > 0) {
      const mentors = await this.mentorService.findByIds(mentorIds);
      if (mentors.length > 0) {
        for (const mentor of mentors) {
          const found = subscription.mentors.find((m) =>
            m._id.equals(mentor._id),
          );
          switch (mode) {
            case 'SUBSCRIBE':
              if (!found) {
                subscription.mentors.unshift(mentor); // Can be optimized since we are increasing the list for search
                modified = true;
              }
              break;
            case 'UNSUBSCRIBE':
              if (found) {
                const index = subscription.mentors.indexOf(found);
                if (index != -1) subscription.mentors.splice(index, 1);
                modified = true;
              }
              break;
          }
        }
      }
    }

    if (topicIds && topicIds.length > 0) {
      const topics = await this.topicService.findByIds(topicIds);
      if (topics.length > 0) {
        for (const topic of topics) {
          const found = subscription.topics.find((t) =>
            t._id.equals(topic._id),
          );
          switch (mode) {
            case 'SUBSCRIBE':
              if (!found) {
                subscription.topics.unshift(topic); // Can be optimized since we are increasing the list for search
                modified = true;
              }
              break;
            case 'UNSUBSCRIBE':
              if (found) {
                const index = subscription.topics.indexOf(found);
                if (index != -1) subscription.topics.splice(index, 1);
                modified = true;
              }
              break;
          }
        }
      }
    }

    if (!modified) return subscription;

    return await this.update(subscription);
  }

  async findRecommendedMentors(
    user: User,
    paginationDto: PaginationDto,
  ): Promise<MentorSubscriptionDto[]> {
    const mentors =
      await this.mentorService.findRecommendedMentorsPaginated(paginationDto);

    const data = mentors.map(
      (mentor) => new MentorSubscriptionDto(mentor, false),
    );

    const subscription = await this.findSubscribedMentors(user);

    if (subscription) {
      for (const entry of data) {
        const found = subscription.mentors.find((m) => m._id.equals(entry._id));
        if (found) entry.subscribed = true;
      }
    }
    return data;
  }

  async findRecommendedTopics(
    user: User,
    paginationDto: PaginationDto,
  ): Promise<TopicSubscriptionDto[]> {
    const topics =
      await this.topicService.findRecommendedTopicsPaginated(paginationDto);

    const data = topics.map((topic) => new TopicSubscriptionDto(topic, false));

    const subscription = await this.findSubscribedTopics(user);

    if (subscription) {
      for (const entry of data) {
        const found = subscription.topics.find((t) => t._id.equals(entry._id));
        if (found) entry.subscribed = true;
      }
    }
    return data;
  }

  async findById(id: Types.ObjectId): Promise<Subscription | null> {
    return this.subscriptionModel
      .findOne({ _id: id, status: true })
      .populate('topics')
      .populate('mentors')
      .lean()
      .exec();
  }

  async create(
    subscription: Partial<Subscription>,
  ): Promise<Subscription | null> {
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
      .findOne({ user: user._id, status: true })
      .lean()
      .exec();
  }

  async findSubscriptionForUserPopulated(
    user: User,
  ): Promise<Subscription | null> {
    return this.subscriptionModel
      .findOne({ user: user._id, status: true })
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
      .findOne({ user: user._id, status: true })
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
      .findOne({ user: user._id, status: true })
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
      user: user._id,
      mentors: mentorId,
      status: true,
    });
    return subscription !== null;
  }

  async topicSubscriptionExists(
    user: User,
    topicId: Types.ObjectId,
  ): Promise<boolean> {
    const subscription = await this.subscriptionModel.exists({
      user: user._id,
      topics: topicId,
      status: true,
    });
    return subscription !== null;
  }

  async deleteUserSubscription(user: User) {
    return this.subscriptionModel.deleteOne({ user: user }).lean().exec();
  }
}
