import {
  Body,
  Controller,
  Get,
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
    return this.contentService.createContent(createContentDto, request.user);
  }

  @Put('id/:id')
  async update(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
    @Request() request: ProtectedRequest,
    @Body() updateContentDto: UpdateContentDto,
  ) {
    return await this.contentService.updateContent(
      request.user,
      id,
      updateContentDto,
    );
  }
}
