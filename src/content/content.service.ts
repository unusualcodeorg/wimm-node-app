import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Content } from './schemas/content.schema';
import { User } from '../user/schemas/user.schema';
import { Mentor } from '../mentor/schemas/mentor.schema';
import { Topic } from '../topic/schemas/topic.schema';
import { Subscription } from '../subscription/schemas/subscription.schema';
import { ContentInfoDto } from './dto/content-info.dto';
import { CreateContentDto } from './dto/create-content.dto';
import { TopicService } from '../topic/topic.service';
import { MentorService } from '../mentor/mentor.service';
import { UpdateContentDto } from './dto/update-content.dto';

@Injectable()
export class ContentService {
  constructor(
    @InjectModel(Content.name) private readonly contentModel: Model<Content>,
    private readonly topicService: TopicService,
    private readonly mentorService: MentorService,
  ) {}

  async createContent(
    createContentDto: CreateContentDto,
    admin: User,
  ): Promise<Content> {
    const topicsAndMentors = await this.validateTopicsMentors(
      createContentDto.topics,
      createContentDto.mentors,
    );

    if (
      topicsAndMentors.topics.length == 0 &&
      topicsAndMentors.mentors.length == 0
    ) {
      throw new NotFoundException(
        'Content must have atleast a mentor or a topic',
      );
    }

    const created = await this.contentModel.create({
      ...createContentDto,
      topics: topicsAndMentors.topics,
      mentors: topicsAndMentors.mentors,
      createdBy: admin,
      updatedBy: admin,
    });

    return created.toObject();
  }

  async updateContent(
    admin: User,
    id: Types.ObjectId,
    updateContentDto: UpdateContentDto,
  ): Promise<Content | null> {
    const content = await this.findById(id);
    if (!content) throw new NotFoundException('Content Not Found');

    const topicsAndMentors = await this.validateTopicsMentors(
      updateContentDto.topics,
      updateContentDto.mentors,
    );

    if (topicsAndMentors.topics.length > 0) {
      content.topics = topicsAndMentors.topics.map(
        (id) => ({ _id: id }) as Topic,
      );
    }

    if (topicsAndMentors.mentors.length > 0) {
      content.mentors = topicsAndMentors.mentors.map(
        (id) => ({ _id: id }) as Mentor,
      );
    }

    return this.update({
      _id: content._id,
      ...updateContentDto,
      topics: content.topics,
      mentors: content.mentors,
      updatedBy: admin,
    });
  }

  private async validateTopicsMentors(
    topics: Types.ObjectId[] | undefined,
    mentors: Types.ObjectId[] | undefined,
  ) {
    const topicIds: Types.ObjectId[] = [];
    const mentorIds: Types.ObjectId[] = [];

    if (topics) {
      for (const topicId of topics) {
        if (!this.topicService.exists(topicId))
          throw new NotFoundException(`Topic ${topicId} not found`);
        topicIds.push(topicId);
      }
    }

    if (mentors) {
      for (const mentorId of mentors) {
        if (!this.mentorService.exists(mentorId))
          throw new NotFoundException(`Mentor ${mentorId} not found`);
        mentorIds.push(mentorId);
      }
    }

    return { topics: topicIds, mentors: mentorIds };
  }

  async findOne(id: Types.ObjectId, user: User): Promise<ContentInfoDto> {
    const content = await this.findPublicInfoById(id);
    if (!content) throw new NotFoundException('Content Not Found');

    const likedContent = await this.findUserAndContentLike(user, content);
    return new ContentInfoDto(
      this.statsBoostUp(content),
      likedContent ? true : false,
    );
  }

  async markView(id: Types.ObjectId): Promise<boolean> {
    const content = await this.findById(id);
    if (!content) throw new NotFoundException('Content Not Found');

    if (!content.views) content.views = 0; // fix for older data

    const updated = await this.update({
      _id: content._id,
      views: content.views + 1,
    });

    return updated != null;
  }

  async markShare(id: Types.ObjectId): Promise<boolean> {
    const content = await this.findById(id);
    if (!content) throw new NotFoundException('Content Not Found');

    if (!content.shares) content.shares = 0; // fix for older data

    const updated = await this.update({
      _id: content._id,
      shares: content.shares + 1,
    });

    return updated != null;
  }

  async markLike(id: Types.ObjectId, user: User): Promise<boolean> {
    const content = await this.findById(id);
    if (!content) throw new NotFoundException('Content Not Found');

    const likedContent = await this.findUserAndContentLike(user, content);

    if (!likedContent) {
      const updated = await this.addLikeForUser(
        content,
        user,
        content.likes + 1,
      );

      return updated != null;
    }

    return true;
  }

  async removeLike(id: Types.ObjectId, user: User): Promise<boolean> {
    const content = await this.findById(id);
    if (!content) throw new NotFoundException('Content Not Found');

    const likedContent = await this.findUserAndContentLike(user, content);

    if (likedContent) {
      const updated = await this.removeLikeForUser(
        content,
        user,
        content.likes - 1,
      );
      return updated != null;
    }

    return true;
  }

  async findById(id: Types.ObjectId): Promise<Content | null> {
    return this.contentModel.findOne({ _id: id, status: true }).lean().exec();
  }

  private async update(content: Partial<Content>): Promise<Content | null> {
    return this.contentModel
      .findByIdAndUpdate(content._id, content, { new: true })
      .lean()
      .exec();
  }

  async remove(content: Content): Promise<Content | null> {
    return this.contentModel
      .findByIdAndUpdate(
        content._id,
        { $set: { status: false } },
        { new: true },
      )
      .lean()
      .exec();
  }

  async findByIdPopulated(id: Types.ObjectId): Promise<Content | null> {
    return this.contentModel
      .findById(id)
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id',
      })
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

  async findPublicInfoById(id: Types.ObjectId): Promise<Content | null> {
    return this.contentModel
      .findOne({
        _id: id,
        status: true,
        private: { $ne: true },
      })
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id name profilePicUrl',
      })
      .lean()
      .exec();
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

  async findPrivateInfoById(id: Types.ObjectId): Promise<Content | null> {
    return this.contentModel
      .findById(id)
      .select('+submit')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id',
      })
      .lean()
      .exec();
  }

  async addLikeForUser(
    content: Content,
    user: User,
    likes: number,
  ): Promise<Content | null> {
    return this.contentModel
      .findByIdAndUpdate(
        content._id,
        { $push: { likedBy: user._id }, likes: likes },
        { new: true },
      )
      .lean()
      .exec();
  }

  async removeLikeForUser(
    content: Content,
    user: User,
    likes: number,
  ): Promise<Content | null> {
    return this.contentModel
      .findByIdAndUpdate(
        content._id,
        { $pull: { likedBy: user._id }, likes: likes },
        { new: true },
      )
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

  async findUserAndContentLike(
    user: User,
    content: Content,
  ): Promise<Content | null> {
    return this.contentModel
      .findOne({
        status: true,
        likedBy: user._id,
        _id: content._id,
      })
      .select('-status -private')
      .lean()
      .exec();
  }

  private statsBoostUp(content: Content) {
    if (content) {
      if (content.likes) content.likes = content.likes + 9 * content.likes;
      if (content.views) content.views = content.views + 17 * content.views;
      if (content.shares) content.shares = content.shares + 7 * content.shares;
    }
    return content;
  }
}
