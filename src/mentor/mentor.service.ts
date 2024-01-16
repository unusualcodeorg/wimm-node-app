import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Mentor } from './schemas/mentor.schema';
import { User } from '../user/schemas/user.schema';
import { CreateMentorDto } from './dto/create-mentor.dto';
import { UpdateMentorDto } from './dto/update-mentor.dto';
import { PaginationDto } from '../common/pagination.dto';

@Injectable()
export class MentorService {
  constructor(
    @InjectModel(Mentor.name) private readonly mentorModel: Model<Mentor>,
  ) {}

  INFO_PARAMETERS = '-description -status';

  async create(admin: User, createMentorDto: CreateMentorDto): Promise<Mentor> {
    const created = await this.mentorModel.create({
      ...createMentorDto,
      createdBy: admin,
      updatedBy: admin,
    });
    return created.toObject();
  }

  async update(
    admin: User,
    mentorId: Types.ObjectId,
    updateMentorDto: UpdateMentorDto,
  ): Promise<Mentor | null> {
    const mentor = await this.findById(mentorId);
    if (!mentor) throw new NotFoundException('Mentor not found');

    return this.mentorModel
      .findByIdAndUpdate(
        mentor._id,
        {
          ...updateMentorDto,
          updatedBy: admin,
        },
        { new: true },
      )
      .lean()
      .exec();
  }

  async delete(mentorId: Types.ObjectId): Promise<Mentor | null> {
    const mentor = await this.findById(mentorId);
    if (!mentor) throw new NotFoundException('Mentor not found');
    return this.mentorModel
      .findByIdAndUpdate(mentor._id, { $set: { status: false } }, { new: true })
      .lean()
      .exec();
  }

  async deleteFromDb(mentor: Mentor) {
    return this.mentorModel.findByIdAndDelete(mentor._id);
  }

  async exists(id: Types.ObjectId): Promise<boolean> {
    const exists = await this.mentorModel.exists(id);
    return exists != null;
  }

  async findById(id: Types.ObjectId): Promise<Mentor | null> {
    return this.mentorModel.findOne({ _id: id, status: true }).lean().exec();
  }

  async findByIds(ids: Types.ObjectId[]): Promise<Mentor[]> {
    return this.mentorModel
      .find({ _id: { $in: ids }, status: true })
      .select(this.INFO_PARAMETERS)
      .lean()
      .exec();
  }

  async findMentorsPaginated(paginationDto: PaginationDto): Promise<Mentor[]> {
    return this.mentorModel
      .find({ status: true })
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
      .select(this.INFO_PARAMETERS)
      .sort({ updatedAt: -1 })
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
    paginationDto: PaginationDto,
  ): Promise<Mentor[]> {
    return this.mentorModel
      .find({ status: true })
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
      .select(this.INFO_PARAMETERS)
      .sort({ score: -1 })
      .lean()
      .exec();
  }
}
