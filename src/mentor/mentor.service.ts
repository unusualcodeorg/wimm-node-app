import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Mentor } from './schemas/mentor.schema';

@Injectable()
export class MentorService {
  constructor(
    @InjectModel(Mentor.name) private readonly mentorModel: Model<Mentor>,
  ) {}

  INFO_PARAMETERS = '-description -status';

  async findById(id: Types.ObjectId): Promise<Mentor | null> {
    return this.mentorModel.findOne({ _id: id, status: true }).lean().exec();
  }

  async create(mentor: Mentor): Promise<Mentor> {
    const created = await this.mentorModel.create(mentor);
    return created.toObject();
  }

  async update(mentor: Mentor): Promise<Mentor | null> {
    return this.mentorModel
      .findByIdAndUpdate(mentor._id, mentor, { new: true })
      .lean()
      .exec();
  }

  async findMentorsPaginated(
    pageNumber: number,
    limit: number,
  ): Promise<Mentor[]> {
    return this.mentorModel
      .find({ status: true })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .select(this.INFO_PARAMETERS)
      .sort({ updatedAt: -1 })
      .lean()
      .exec();
  }

  async findByIds(ids: Types.ObjectId[]): Promise<Mentor[]> {
    return this.mentorModel
      .find({ _id: { $in: ids }, status: true })
      .select(this.INFO_PARAMETERS)
      .lean()
      .exec();
  }

  async search(query: string, limit: number): Promise<Mentor[]> {
    return this.mentorModel
      .find({
        $text: { $search: query, $caseSensitive: false },
        status: true,
      })
      .select(this.INFO_PARAMETERS)
      .limit(limit)
      .lean()
      .exec();
  }

  async searchLike(query: string, limit: number): Promise<Mentor[]> {
    return this.mentorModel
      .find()
      .and([
        { status: true },
        {
          $or: [
            { name: { $regex: `.*${query}.*`, $options: 'i' } },
            { occupation: { $regex: `.*${query}.*`, $options: 'i' } },
            { title: { $regex: `.*${query}.*`, $options: 'i' } },
          ],
        },
      ])
      .select(this.INFO_PARAMETERS)
      .limit(limit)
      .lean()
      .exec();
  }

  async findRecommendedMentors(limit: number): Promise<Mentor[]> {
    return this.mentorModel
      .find({ status: true })
      .limit(limit)
      .select(this.INFO_PARAMETERS)
      .sort({ score: -1 })
      .lean()
      .exec();
  }

  async findRecommendedMentorsPaginated(
    pageNumber: number,
    limit: number,
  ): Promise<Mentor[]> {
    return this.mentorModel
      .find({ status: true })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .select(this.INFO_PARAMETERS)
      .sort({ score: -1 })
      .lean()
      .exec();
  }

  async remove(topic: Mentor): Promise<Mentor | null> {
    topic.status = false;
    return this.mentorModel
      .findByIdAndUpdate(topic._id, { $set: { status: false } }, { new: true })
      .lean()
      .exec();
  }
}
