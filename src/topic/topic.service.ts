import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Topic } from './schemas/topic.schema';
import { User } from '../user/schemas/user.schema';
import { CreateTopicDto } from './dto/create-topic.dto';
import { UpdateTopicDto } from './dto/update-topic.dto';
import { PaginationDto } from '../common/pagination.dto';

@Injectable()
export class TopicService {
  constructor(
    @InjectModel(Topic.name) private readonly topicModel: Model<Topic>,
  ) {}

  INFO_PARAMETERS = '-description -status';

  async create(admin: User, createTopicDto: CreateTopicDto): Promise<Topic> {
    const created = await this.topicModel.create({
      ...createTopicDto,
      createdBy: admin,
      updatedBy: admin,
    });
    return created.toObject();
  }

  async update(
    admin: User,
    topicId: Types.ObjectId,
    updateTopicDto: UpdateTopicDto,
  ): Promise<Topic | null> {
    const topic = await this.findById(topicId);
    if (!topic) throw new NotFoundException('Topic not found');

    return this.topicModel
      .findByIdAndUpdate(
        topic._id,
        {
          ...updateTopicDto,
          updatedBy: admin,
        },
        { new: true },
      )
      .lean()
      .exec();
  }

  async delete(topicId: Types.ObjectId): Promise<Topic | null> {
    const topic = await this.findById(topicId);
    if (!topic) throw new NotFoundException('Topic not found');
    return this.topicModel
      .findByIdAndUpdate(topic._id, { $set: { status: false } }, { new: true })
      .lean()
      .exec();
  }

  async deleteFromDb(topic: Topic) {
    return this.topicModel.findByIdAndDelete(topic._id);
  }

  async exists(id: Types.ObjectId): Promise<boolean> {
    const exists = await this.topicModel.exists(id);
    return exists != null;
  }

  async findById(id: Types.ObjectId): Promise<Topic | null> {
    return this.topicModel.findOne({ _id: id, status: true }).lean().exec();
  }

  async findByIds(ids: Types.ObjectId[]): Promise<Topic[]> {
    return this.topicModel
      .find({ _id: { $in: ids }, status: true })
      .select(this.INFO_PARAMETERS)
      .lean()
      .exec();
  }

  async findTopicsPaginated(paginationDto: PaginationDto): Promise<Topic[]> {
    return this.topicModel
      .find({ status: true })
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
      .select(this.INFO_PARAMETERS)
      .sort({ updatedAt: -1 })
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
    paginationDto: PaginationDto,
  ): Promise<Topic[]> {
    return this.topicModel
      .find({ status: true })
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
      .select(this.INFO_PARAMETERS)
      .sort({ score: -1 })
      .lean()
      .exec();
  }
}
