import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Bookmark } from './schemas/bookmark.schema';
import { User } from '../user/schemas/user.schema';
import { ContentService } from '../content/content.service';
import { Content } from '../content/schemas/content.schema';

@Injectable()
export class BookmarkService {
  constructor(
    @InjectModel(Bookmark.name) private readonly bookmarkModel: Model<Bookmark>,
    private readonly contentService: ContentService,
  ) {}

  async create(
    user: User,
    contentId: Types.ObjectId,
  ): Promise<Bookmark | null> {
    const content = await this.contentService.findById(contentId);
    if (!content) throw new NotFoundException('Content Not Found');

    if (content.private) throw new ForbiddenException('Content Not Avilable');

    const bookmark = await this.findBookmark(user, content);
    if (bookmark) throw new BadRequestException('Bookmark already exists');

    return await this.bookmarkModel.create({
      user: user._id,
      content: content._id,
    });
  }

  async delete(
    user: User,
    contentId: Types.ObjectId,
  ): Promise<Bookmark | null> {
    const content = await this.contentService.findById(contentId);
    if (!content) throw new NotFoundException('Content Not Found');

    const bookmark = await this.findBookmark(user, content);
    if (!bookmark) throw new BadRequestException('Bookmark Not Found');

    return await this.remove(bookmark);
  }

  async findById(id: Types.ObjectId): Promise<Bookmark | null> {
    return this.bookmarkModel
      .findOne({ _id: id, status: true })
      .populate('user', 'status')
      .populate('content', 'status private')
      .lean()
      .exec();
  }

  async update(bookmark: Bookmark): Promise<Bookmark | null> {
    return this.bookmarkModel
      .findByIdAndUpdate(bookmark._id, bookmark, { new: true })
      .lean()
      .exec();
  }

  async findBookmark(user: User, content: Content): Promise<Bookmark | null> {
    return this.bookmarkModel
      .findOne({
        user: user._id,
        content: content._id,
        status: true,
      })
      .populate('user', 'status')
      .populate('content', 'status private')
      .lean()
      .exec();
  }

  async findBookmarks(user: User): Promise<Bookmark[]> {
    return this.bookmarkModel
      .find({ user: user._id, status: true })
      .sort({ createdAt: -1 })
      .lean()
      .exec();
  }

  async remove(bookmark: Bookmark): Promise<any> {
    return this.bookmarkModel
      .updateOne(
        { _id: bookmark._id },
        { $set: { status: false } },
        { new: true },
      )
      .lean()
      .exec();
  }

  async deleteUserBookmarks(user: User) {
    return this.bookmarkModel.deleteMany({ user: user }).lean().exec();
  }
}
