import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Request,
  UseInterceptors,
} from '@nestjs/common';
import { ContentService } from './content.service';
import { ProtectedRequest } from '../core/http/request';
import { MongoIdTransformer } from '../common/mongoid.transformer';
import { Types } from 'mongoose';
import { ContentInfoDto } from './dto/content-info.dto';
import { MongoIdDto } from '../common/mongoid.dto';
import { CacheInterceptor } from '@nestjs/cache-manager';

@Controller('content')
export class ContentController {
  constructor(private readonly contentService: ContentService) {}

  @UseInterceptors(CacheInterceptor)
  @Get('id/:id')
  async findOne(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
    @Request() request: ProtectedRequest,
  ): Promise<ContentInfoDto> {
    return await this.contentService.findOne(id, request.user);
  }

  @Post('mark/view')
  async markView(@Body() mongoIdDto: MongoIdDto): Promise<string> {
    const marked = await this.contentService.markView(mongoIdDto.id);
    if (!marked) return 'Content view marked failure.';
    return 'Content view marked successfully.';
  }

  @Post('mark/like')
  async markLike(
    @Body() mongoIdDto: MongoIdDto,
    @Request() request: ProtectedRequest,
  ): Promise<string> {
    const marked = await this.contentService.markLike(
      mongoIdDto.id,
      request.user,
    );
    if (!marked) return 'Content like marked failure.';
    return 'Content liked successfully.';
  }

  @Post('mark/unlike')
  async removeLike(
    @Body() mongoIdDto: MongoIdDto,
    @Request() request: ProtectedRequest,
  ): Promise<string> {
    const marked = await this.contentService.removeLike(
      mongoIdDto.id,
      request.user,
    );
    if (!marked) return 'Content like removed failure.';
    return 'Content like removed successfully.';
  }

  @Post('mark/share')
  async markShare(@Body() mongoIdDto: MongoIdDto): Promise<string> {
    const marked = await this.contentService.markShare(mongoIdDto.id);
    if (!marked) return 'Content share marked failure.';
    return 'Content share marked successfully.';
  }
}
