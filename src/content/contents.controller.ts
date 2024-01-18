import { Controller, Get, Param, Query, Request } from '@nestjs/common';
import { ContentsService } from './contents.service';
import { ProtectedRequest } from '../core/http/request';
import { MongoIdTransformer } from '../common/mongoid.transformer';
import { Types } from 'mongoose';
import { ContentInfoDto } from './dto/content-info.dto';
import { PaginationDto } from '../common/pagination.dto';
import { PaginationRotatedDto } from './dto/pagination-rotated.dto';

@Controller('contents')
export class ContentsController {
  constructor(private readonly contentsService: ContentsService) {}

  @Get('content/:id/similar')
  async findSimilarContents(
    @Param('id', MongoIdTransformer) contentId: Types.ObjectId,
    @Query() paginationDto: PaginationDto,
    @Request() request: ProtectedRequest,
  ): Promise<ContentInfoDto[]> {
    return await this.contentsService.findSimilarContents(
      request.user,
      contentId,
      paginationDto,
    );
  }

  @Get('mentor/:id')
  async findMentorContents(
    @Param('id', MongoIdTransformer) mentorId: Types.ObjectId,
    @Query() paginationDto: PaginationDto,
  ): Promise<ContentInfoDto[]> {
    return await this.contentsService.findMentorContents(
      mentorId,
      paginationDto,
    );
  }

  @Get('topic/:id')
  async findTopicContents(
    @Param('id', MongoIdTransformer) topicId: Types.ObjectId,
    @Query() paginationDto: PaginationDto,
  ): Promise<ContentInfoDto[]> {
    return await this.contentsService.findTopicContents(topicId, paginationDto);
  }

  @Get('rotated')
  async findRotatedContents(
    @Query() paginationRotatedDto: PaginationRotatedDto,
    @Request() request: ProtectedRequest,
  ): Promise<ContentInfoDto[]> {
    return await this.contentsService.findRotatedContents(
      request.user,
      paginationRotatedDto,
    );
  }

  @Get('my/box')
  async findMyBoxContents(
    @Query() paginationDto: PaginationDto,
    @Request() request: ProtectedRequest,
  ): Promise<ContentInfoDto[]> {
    return await this.contentsService.myboxContents(
      request.user,
      paginationDto,
    );
  }
}
