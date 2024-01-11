import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Topic } from './schemas/topic.schema';

@Injectable()
export class TopicService {
  constructor(
    @InjectModel(Topic.name) private readonly topicModel: Model<Topic>,
  ) {}

  INFO_PARAMETERS = '-description -status';

  async findById(id: Types.ObjectId): Promise<Topic | null> {
    return this.topicModel.findOne({ _id: id, status: true }).lean().exec();
  }

  async create(topic: Topic): Promise<Topic> {
    const created = await this.topicModel.create(topic);
    return created.toObject();
  }

  async update(topic: Topic): Promise<Topic | null> {
    return this.topicModel
      .findByIdAndUpdate(topic._id, topic, { new: true })
      .lean()
      .exec();
  }

  async findTopicsPaginated(
    pageNumber: number,
    limit: number,
  ): Promise<Topic[]> {
    return this.topicModel
      .find({ status: true })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .select(this.INFO_PARAMETERS)
      .sort({ updatedAt: -1 })
      .lean()
      .exec();
  }

  async findByIds(ids: Types.ObjectId[]): Promise<Topic[]> {
    return this.topicModel
      .find({ _id: { $in: ids }, status: true })
      .select(this.INFO_PARAMETERS)
      .lean()
      .exec();
  }

  async search(query: string, limit: number): Promise<Topic[]> {
    return this.topicModel
      .find({
        $text: { $search: query, $caseSensitive: false },
        status: true,
      })
      .select(this.INFO_PARAMETERS)
      .limit(limit)
      .lean()
      .exec();
  }

  async searchLike(query: string, limit: number): Promise<Topic[]> {
    return this.topicModel
      .find()
      .and([
        { status: true },
        {
          $or: [
            { name: { $regex: `.*${query}.*`, $options: 'i' } },
            { title: { $regex: `.*${query}.*`, $options: 'i' } },
          ],
        },
      ])
      .select(this.INFO_PARAMETERS)
      .limit(limit)
      .lean()
      .exec();
  }

  async findRecommendedTopics(limit: number): Promise<Topic[]> {
    return this.topicModel
      .find({ status: true })
      .limit(limit)
      .select(this.INFO_PARAMETERS)
      .sort({ score: -1 })
      .lean()
      .exec();
  }

  async findRecommendedTopicsPaginated(
    pageNumber: number,
    limit: number,
  ): Promise<Topic[]> {
    return this.topicModel
      .find({ status: true })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .select(this.INFO_PARAMETERS)
      .sort({ score: -1 })
      .lean()
      .exec();
  }

  async remove(topic: Topic): Promise<Topic | null> {
    topic.status = false;
    return this.topicModel
      .findByIdAndUpdate(topic._id, { $set: { status: false } }, { new: true })
      .lean()
      .exec();
  }
}
