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
import { SubscriptionService } from '../subscription/subscription.service';
import { PaginationRotatedDto } from './dto/pagination-rotated.dto';
import { BookmarkService } from '../bookmark/bookmark.service';
import { Bookmark } from '../bookmark/schemas/bookmark.schema';

@Injectable()
export class ContentsService {
  constructor(
    @InjectModel(Content.name) private readonly contentModel: Model<Content>,
    private readonly contentService: ContentService,
    private readonly topicService: TopicService,
    private readonly mentorService: MentorService,
    private readonly subscriptionService: SubscriptionService,
    private readonly bookmarkService: BookmarkService,
  ) {}

  async findRotatedContents(
    user: User,
    paginationRotatedDto: PaginationRotatedDto,
  ): Promise<ContentInfoDto[]> {
    const allContents: Content[] = [];

    const subscription =
      await this.subscriptionService.findSubscriptionForUser(user);

    if (subscription) {
      if (
        paginationRotatedDto.empty == true ||
        paginationRotatedDto.pageNumber == 1
      ) {
        const latestContents = await this.findSubscriptionContentsPaginated(
          subscription,
          paginationRotatedDto,
        );
        allContents.push(...latestContents);
      }
    }

    const contents = await this.findContentsPaginated(paginationRotatedDto);

    for (const content of contents) {
      const found = allContents.find((c) => c._id.equals(content._id));
      if (!found) allContents.push(content);
    }

    const likedContents = await this.findUserAndContentsLike(
      user,
      allContents.map((content) => content._id),
    );

    allContents.forEach((content) => this.contentService.statsBoostUp(content));

    const contentInfodtos = allContents.map(
      (content) => new ContentInfoDto(content),
    );

    for (const dto of contentInfodtos) {
      const found = likedContents.find((liked) => liked._id.equals(dto._id));
      dto.liked = found ? true : false;
    }

    return contentInfodtos;
  }

  async findSimilarContents(
    user: User,
    contentId: Types.ObjectId,
    paginationDto: PaginationDto,
  ): Promise<ContentInfoDto[]> {
    const content = await this.contentService.findInfoById(user, contentId);
    if (!content) throw new NotFoundException('Content Not Found');

    const contents = await this.searchSimilar(
      content,
      `${content.title} ${content.subtitle}`,
      paginationDto,
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
      paginationDto,
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
      paginationDto,
    );

    contents.forEach((content) => this.contentService.statsBoostUp(content));

    return contents.map((content) => new ContentInfoDto(content));
  }

  async findContentsPaginated(
    paginationDto: PaginationDto,
  ): Promise<Content[]> {
    return this.contentModel
      .find({ status: true, private: { $ne: true } })
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id name profilePicUrl',
      })
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
      .sort({ updatedAt: -1 })
      .lean()
      .exec();
  }

  async findMentorContentsPaginated(
    mentor: Mentor,
    paginationDto: PaginationDto,
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
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
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
    paginationDto: PaginationDto,
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
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
      .sort({ score: -1, updatedAt: -1 })
      .lean()
      .exec();
  }

  async myboxContents(
    user: User,
    paginationDto: PaginationDto,
  ): Promise<ContentInfoDto[]> {
    const bookmarks = await this.bookmarkService.findBookmarks(user);
    const contents = await this.findUserBoxContentPaginated(
      user,
      bookmarks,
      paginationDto,
    );
    return contents.map((content) => new ContentInfoDto(content));
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
    paginationDto: PaginationDto,
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
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
      .lean()
      .exec();
  }

  async findSubscriptionContentsPaginated(
    subscription: Subscription,
    paginationDto: PaginationDto,
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
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
      .sort({ updatedAt: -1 })
      .lean()
      .exec();
  }

  async findUserContentsPaginated(
    user: User,
    paginationDto: PaginationDto,
  ): Promise<Content[]> {
    return this.contentModel
      .find({ createdBy: user._id, status: true })
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id',
      })
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
      .sort({ updatedAt: -1 })
      .lean()
      .exec();
  }

  async findUserBoxContentPaginated(
    user: User,
    bookmarks: Bookmark[],
    paginationDto: PaginationDto,
  ): Promise<Content[]> {
    return this.contentModel
      .find()
      .and([
        { status: true },
        {
          $or: [
            { createdBy: user._id },
            { _id: { $in: bookmarks.map((b) => b._id) } },
          ],
        },
      ])
      .select('-status +submit')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id',
      })
      .skip(paginationDto.pageItemCount * (paginationDto.pageNumber - 1))
      .limit(paginationDto.pageItemCount)
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
