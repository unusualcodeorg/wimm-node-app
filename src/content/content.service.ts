import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Category, Content } from './schemas/content.schema';
import { User } from '../user/schemas/user.schema';
import { Mentor } from '../mentor/schemas/mentor.schema';
import { Topic } from '../topic/schemas/topic.schema';
import { ContentInfoDto } from './dto/content-info.dto';
import { CreateContentDto } from './dto/create-content.dto';
import { TopicService } from '../topic/topic.service';
import { MentorService } from '../mentor/mentor.service';
import { UpdateContentDto } from './dto/update-content.dto';
import { CreatePrivateContentDto } from './dto/create-private-content.dto';

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

  async createPrivateContent(
    createPrivateContentDto: CreatePrivateContentDto,
    user: User,
  ): Promise<ContentInfoDto> {
    if (
      (createPrivateContentDto.extra.includes('https://youtu.be') ||
        createPrivateContentDto.extra.includes(
          'https://www.youtube.com/watch',
        )) &&
      createPrivateContentDto.category != Category.YOUTUBE
    ) {
      throw new BadRequestException('Content category must be YOUTUBE');
    }

    const created = await this.contentModel.create({
      ...createPrivateContentDto,
      private: true,
      createdBy: user,
      updatedBy: user,
    });

    return new ContentInfoDto({ ...created.toObject(), createdBy: user });
  }

  async submitPrivateContent(
    user: User,
    id: Types.ObjectId,
  ): Promise<Content | null> {
    return this.updatePrivateContent(user, id, { submit: true });
  }

  async unsubmitPrivateContent(
    user: User,
    id: Types.ObjectId,
  ): Promise<Content | null> {
    return this.updatePrivateContent(user, id, { submit: false });
  }

  async deletePrivateContent(
    user: User,
    id: Types.ObjectId,
  ): Promise<Content | null> {
    return this.updatePrivateContent(user, id, { status: false });
  }

  private async updatePrivateContent(
    user: User,
    id: Types.ObjectId,
    updater: Partial<Content>,
  ): Promise<Content | null> {
    const content = await this.findPrivateInfoById(id);
    if (!content) throw new NotFoundException('Content Not Found');

    if (!user._id.equals(content.createdBy._id))
      throw new ForbiddenException('Permission denied');

    return await this.update({
      _id: content._id,
      ...updater,
    });
  }

  async publishContent(
    admin: User,
    id: Types.ObjectId,
  ): Promise<Content | null> {
    const content = await this.findById(id);
    if (!content) throw new NotFoundException('Content Not Found');

    return await this.update({
      _id: content._id,
      general: true,
      private: false,
      updatedBy: admin,
    });
  }

  async unpublishContent(
    admin: User,
    id: Types.ObjectId,
  ): Promise<Content | null> {
    const content = await this.findById(id);
    if (!content) throw new NotFoundException('Content Not Found');

    return await this.update({
      _id: content._id,
      general: false,
      private: true,
      updatedBy: admin,
    });
  }

  async findOne(id: Types.ObjectId, user: User): Promise<ContentInfoDto> {
    const content = await this.findInfoById(user, id);
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

    if (!content.likes) content.likes = 0; // fix for older data

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

    if (!content.likes) content.likes = 0; // fix for older data

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

  async delete(contentId: Types.ObjectId): Promise<Content | null> {
    const content = await this.findById(contentId);
    if (!content) throw new NotFoundException('Content not found');
    return this.contentModel
      .findByIdAndUpdate(
        content._id,
        { $set: { status: false } },
        { new: true },
      )
      .lean()
      .exec();
  }

  async deleteFromDb(content: Content) {
    return this.contentModel.findByIdAndDelete(content._id);
  }

  async findByIdPopulated(id: Types.ObjectId): Promise<Content | null> {
    return this.contentModel
      .findOne({ _id: id, status: true })
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

  async findInfoById(user: User, id: Types.ObjectId): Promise<Content | null> {
    return this.contentModel
      .findOne()
      .and([
        { _id: id, status: true },
        {
          $or: [{ createdBy: user._id }, { private: { $ne: true } }],
        },
      ])
      .select('-status -private')
      .populate({
        path: 'createdBy',
        match: { status: true },
        select: '_id name profilePicUrl',
      })
      .lean()
      .exec();
  }

  async findPrivateInfoById(id: Types.ObjectId): Promise<Content | null> {
    return this.contentModel
      .findOne({ _id: id, status: true })
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

  statsBoostUp(content: Content) {
    if (!content.likes) content.likes = 1;
    if (!content.views) content.views = 1;
    if (!content.shares) content.shares = 1;

    content.likes = content.likes + 9 * content.likes;
    content.views = content.views + 17 * content.views;
    content.shares = content.shares + 7 * content.shares;

    return content;
  }
}
