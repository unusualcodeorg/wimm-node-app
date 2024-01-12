import {
  Body,
  Controller,
  Delete,
  InternalServerErrorException,
  Param,
  Post,
  Put,
  Request,
} from '@nestjs/common';
import { ContentService } from './content.service';
import { ProtectedRequest } from '../core/http/request';
import { ContentInfoDto } from './dto/content-info.dto';
import { CreatePrivateContentDto } from './dto/create-private-content.dto';
import { MongoIdDto } from '../common/mongoid.dto';
import { Types } from 'mongoose';
import { MongoIdTransformer } from '../common/mongoid.transformer';

@Controller('content/private')
export class ContentPrivateController {
  constructor(private readonly contentService: ContentService) {}

  @Post()
  async create(
    @Body() createPrivateContentDto: CreatePrivateContentDto,
    @Request() request: ProtectedRequest,
  ): Promise<ContentInfoDto> {
    const content = this.contentService.createPrivateContent(
      createPrivateContentDto,
      request.user,
    );
    if (!content) throw new InternalServerErrorException();
    return content;
  }

  @Put('submit')
  async submit(
    @Body() mongoIdDto: MongoIdDto,
    @Request() request: ProtectedRequest,
  ): Promise<string> {
    const content = await this.contentService.submitPrivateContent(
      request.user,
      mongoIdDto.id,
    );
    if (!content) throw new InternalServerErrorException('Not able to submit');
    return 'Content submitted successfully';
  }

  @Put('unsubmit')
  async unsubmit(
    @Body() mongoIdDto: MongoIdDto,
    @Request() request: ProtectedRequest,
  ): Promise<string> {
    const content = await this.contentService.unsubmitPrivateContent(
      request.user,
      mongoIdDto.id,
    );
    if (!content)
      throw new InternalServerErrorException('Not able to remove submission');
    return 'Content submission removed successfully';
  }

  @Delete('id/:id')
  async delete(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
    @Request() request: ProtectedRequest,
  ): Promise<string> {
    const content = await this.contentService.deletePrivateContent(
      request.user,
      id,
    );
    if (!content)
      throw new InternalServerErrorException('Not able to delete content');
    return 'Content deleted successfully';
  }
}
