import { Controller, Get, Param, Request } from '@nestjs/common';
import { ContentService } from './content.service';
import { ProtectedRequest } from '../core/http/request';
import { MongoIdTransformer } from '../common/mongoid.transformer';
import { Types } from 'mongoose';
import { ContentInfoDto } from './dto/content-info.dto';

@Controller('content')
export class ContentController {
  constructor(private readonly contentService: ContentService) {}

  @Get('id/:id')
  async findOne(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
    @Request() request: ProtectedRequest,
  ): Promise<ContentInfoDto> {
    return await this.contentService.findOne(id, request.user);
  }
}
