import {
  Body,
  Controller,
  InternalServerErrorException,
  Post,
  Request,
} from '@nestjs/common';
import { ContentService } from './content.service';
import { ProtectedRequest } from '../core/http/request';
import { ContentInfoDto } from './dto/content-info.dto';
import { CreatePrivateContentDto } from './dto/create-private-content.dto';

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
}
