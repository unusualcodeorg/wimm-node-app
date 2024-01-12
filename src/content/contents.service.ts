import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Content } from './schemas/content.schema';
import { Model, Types } from 'mongoose';
import { TopicService } from '../topic/topic.service';
import { MentorService } from '../mentor/mentor.service';
import { Mentor } from '../mentor/schemas/mentor.schema';
import { Topic } from '../topic/schemas/topic.schema';
import { User } from '../user/schemas/user.schema';
import { Subscription } from '../subscription/schemas/subscription.schema';
import { PaginationDto } from '../common/pagination.dto';
import { ContentService } from './content.service';
import { ContentInfoDto } from './dto/content-info.dto';

@Injectable()
export class ContentsService {
  constructor(
    @InjectModel(Content.name) private readonly contentModel: Model<Content>,
    private readonly contentService: ContentService,
    private readonly topicService: TopicService,
    private readonly mentorService: MentorService,
  ) {}

  // TODO
  // async findRotatedContents(
  //   user: User,
  //   paginationRotatedDto: PaginationRotatedDto,
  // ): Promise<ContentInfoDto[]> {}

  async findSimilarContents(
    user: User,
    contentId: Types.ObjectId,
    paginationDto: PaginationDto,
  ): Promise<ContentInfoDto[]> {
    const content = await this.contentService.findPublicInfoById(contentId);
    if (!content) throw new NotFoundException('Content Not Found');

    const contents = await this.searchSimilar(
      content,
      `${content.title} ${content.subtitle}`,
      paginationDto.pageNumber,
      paginationDto.pageItemCount,
    );

    contents.forEach((content) => this.contentService.statsBoostUp(content));

    const contentInfoDtos = contents.map(
      (content) => new ContentInfoDto(content),
    );

    if (contentInfoDtos.length > 0) {
      const likedContents = await this.findUserAndContentsLike(
        user,
        contentInfoDtos.map((c) => c._id),
      );

      for (const dto of contentInfoDtos) {
        const found = likedContents.find((c) => c._id.equals(dto._id));
        dto.liked = found ? true : false;
      }
    }

    return contentInfoDtos;
  }

  async findMentorContents(
    mentorId: Types.ObjectId,
    paginationDto: PaginationDto,
  ): Promise<ContentInfoDto[]> {
    const mentor = await this.mentorService.findById(mentorId);
    if (!mentor) throw new NotFoundException('Mentor Not Found');

    const contents = await this.findMentorContentsPaginated(
      mentor,
      paginationDto.pageNumber,
      paginationDto.pageItemCount,
    );

    contents.forEach((content) => this.contentService.statsBoostUp(content));

    return contents.map((content) => new ContentInfoDto(content));
  }

  async findTopicContents(
    topicId: Types.ObjectId,
    paginationDto: PaginationDto,
  ): Promise<ContentInfoDto[]> {
    const topic = await this.topicService.findById(topicId);
    if (!topic) throw new NotFoundException('Topic Not Found');

    const contents = await this.findTopicContentsPaginated(
      topic,
      paginationDto.pageNumber,
      paginationDto.pageItemCount,
    );

    contents.forEach((content) => this.contentService.statsBoostUp(content));

    return contents.map((content) => new ContentInfoDto(content));
  }

  async findContentsPaginated(
    pageNumber: number,
    limit: number,
  ): Promise<Content[]> {
    return this.contentModel
      .find({ status: true, private: { $ne: true } })
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id name profilePicUrl',
      })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .sort({ updatedAt: -1 })
      .lean()
      .exec();
  }

  async findMentorContentsPaginated(
    mentor: Mentor,
    pageNumber: number,
    limit: number,
  ): Promise<Content[]> {
    return this.contentModel
      .find({
        mentors: mentor._id,
        status: true,
        private: { $ne: true },
      })
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id',
      })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .sort({ score: -1, updatedAt: -1 })
      .lean()
      .exec();
  }

  async search(query: string, limit: number): Promise<Content[]> {
    return this.contentModel
      .find({
        $text: { $search: query, $caseSensitive: false },
        status: true,
        private: { $ne: true },
      })
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id',
      })
      .limit(limit)
      .sort({ score: -1, updatedAt: -1 })
      .lean()
      .exec();
  }

  async findTopicContentsPaginated(
    topic: Topic,
    pageNumber: number,
    limit: number,
  ): Promise<Content[]> {
    return this.contentModel
      .find({
        topics: topic._id,
        status: true,
        private: { $ne: true },
      })
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id',
      })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .sort({ score: -1, updatedAt: -1 })
      .lean()
      .exec();
  }

  async searchLike(query: string, limit: number): Promise<Content[]> {
    return this.contentModel
      .find({
        title: { $regex: `.*${query}.*`, $options: 'i' },
        status: true,
        private: { $ne: true },
      })
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id',
      })
      .limit(limit)
      .sort({ score: -1, updatedAt: -1 })
      .lean()
      .exec();
  }

  async searchSimilar(
    content: Content,
    query: string,
    pageNumber: number,
    limit: number,
  ): Promise<Content[]> {
    return this.contentModel
      .find(
        {
          $text: { $search: query, $caseSensitive: false },
          status: true,
          private: { $ne: true },
          category: content.category,
          _id: { $ne: content._id },
        },
        {
          similarity: { $meta: 'textScore' },
        },
      )
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id name profilePicUrl',
      })
      .sort({ similarity: { $meta: 'textScore' } })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .lean()
      .exec();
  }

  async findSubscriptionContentsPaginated(
    subscription: Subscription,
    pageNumber: number,
    limit: number,
  ): Promise<Content[]> {
    return this.contentModel
      .find()
      .and([
        { status: true },
        { private: { $ne: true } },
        {
          $or: [
            { mentors: { $in: subscription.mentors.flatMap((m) => m._id) } },
            { topics: { $in: subscription.topics.flatMap((t) => t._id) } },
            { general: { $eq: true }, submit: true },
          ],
        },
      ])
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id name profilePicUrl',
      })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .sort({ updatedAt: -1 })
      .lean()
      .exec();
  }

  async findUserContentsPaginated(
    user: User,
    pageNumber: number,
    limit: number,
  ): Promise<Content[]> {
    return this.contentModel
      .find({ createdBy: user._id, status: true })
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id',
      })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .sort({ updatedAt: -1 })
      .lean()
      .exec();
  }

  async findUserBoxContentPaginated(
    user: User,
    bookmarkedContentIds: Types.ObjectId[],
    pageNumber: number,
    limit: number,
  ): Promise<Content[]> {
    return this.contentModel
      .find()
      .and([
        { status: true },
        {
          $or: [
            { createdBy: user._id },
            { _id: { $in: bookmarkedContentIds } },
          ],
        },
      ])
      .select('-status +submit')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id',
      })
      .skip(limit * (pageNumber - 1))
      .limit(limit)
      .sort({ createdAt: -1 })
      .lean()
      .exec();
  }

  async findUserAndContentsLike(
    user: User,
    contentIds: Types.ObjectId[],
  ): Promise<Content[]> {
    return this.contentModel
      .find({
        status: true,
        likedBy: user._id,
        _id: { $in: contentIds },
      })
      .select('-status -private')
      .lean()
      .exec();
  }
}
