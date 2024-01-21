import {
  Body,
  Controller,
  Delete,
  Get,
  InternalServerErrorException,
  NotFoundException,
  Param,
  Post,
  Put,
  Request,
} from '@nestjs/common';
import { ContentService } from './content.service';
import { Roles } from '../auth/decorators/roles.decorator';
import { RoleCode } from '../auth/schemas/role.schema';
import { MongoIdTransformer } from '../common/mongoid.transformer';
import { Types } from 'mongoose';
import { Content } from './schemas/content.schema';
import { CreateContentDto } from './dto/create-content.dto';
import { ProtectedRequest } from '../core/http/request';
import { UpdateContentDto } from './dto/update-content.dto';
import { MongoIdDto } from '../common/mongoid.dto';

@Roles([RoleCode.ADMIN])
@Controller('content/admin')
export class ContentAdminController {
  constructor(private readonly contentService: ContentService) {}

  @Get('id/:id')
  async findOne(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
  ): Promise<Content> {
    const content = await this.contentService.findById(id);
    if (!content) throw new NotFoundException();
    return content;
  }

  @Post()
  async create(
    @Body() createContentDto: CreateContentDto,
    @Request() request: ProtectedRequest,
  ): Promise<Content> {
    const content = this.contentService.createContent(
      createContentDto,
      request.user,
    );
    if (!content) throw new InternalServerErrorException();
    return content;
  }

  @Put('id/:id')
  async update(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
    @Request() request: ProtectedRequest,
    @Body() updateContentDto: UpdateContentDto,
  ): Promise<Content> {
    const content = await this.contentService.updateContent(
      request.user,
      id,
      updateContentDto,
    );
    if (!content) throw new InternalServerErrorException();
    return content;
  }

  @Delete('id/:id')
  async delete(@Param('id', MongoIdTransformer) id: Types.ObjectId) {
    const content = await this.contentService.delete(id);
    if (!content) throw new InternalServerErrorException();
    return content;
  }

  @Put('publish/general')
  async publish(
    @Body() mongoIdDto: MongoIdDto,
    @Request() request: ProtectedRequest,
  ): Promise<string> {
    const content = await this.contentService.publishContent(
      request.user,
      mongoIdDto.id,
    );
    if (!content) throw new InternalServerErrorException('Not able to publish');
    return 'Content published successfully';
  }

  @Put('unpublish/general')
  async unpublish(
    @Body() mongoIdDto: MongoIdDto,
    @Request() request: ProtectedRequest,
  ): Promise<string> {
    const content = await this.contentService.unpublishContent(
      request.user,
      mongoIdDto.id,
    );
    if (!content)
      throw new InternalServerErrorException('Not able to unpublish');
    return 'Content publication removed';
  }
}
