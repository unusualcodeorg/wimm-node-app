import {
  Body,
  Controller,
  Delete,
  InternalServerErrorException,
  Param,
  Post,
  Request,
} from '@nestjs/common';
import { BookmarkService } from './bookmark.service';
import { ProtectedRequest } from '../core/http/request';
import { MongoIdDto } from '../common/mongoid.dto';
import { MongoIdTransformer } from '../common/mongoid.transformer';
import { Types } from 'mongoose';

@Controller('content/bookmark')
export class BookmarkController {
  constructor(private readonly bookmarkService: BookmarkService) {}

  @Post()
  async create(
    @Body() mongoIdDto: MongoIdDto,
    @Request() request: ProtectedRequest,
  ) {
    const bookmark = await this.bookmarkService.create(
      request.user,
      mongoIdDto.id,
    );
    if (!bookmark)
      throw new InternalServerErrorException('Not able to create bookmark');
    return 'Content bookmarked successfully';
  }

  @Delete('id/:id')
  async delete(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
    @Request() request: ProtectedRequest,
  ): Promise<string> {
    const content = await this.bookmarkService.delete(request.user, id);
    if (!content)
      throw new InternalServerErrorException('Not able to delete bookmark');
    return 'Bookmark deleted successfully';
  }
}
