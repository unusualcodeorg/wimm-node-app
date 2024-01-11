import {
  Body,
  Controller,
  Delete,
  Param,
  Post,
  Put,
  Request,
} from '@nestjs/common';
import { MentorService } from './mentor.service';
import { CreateMentorDto } from './dto/create-mentor.dto';
import { Roles } from '../auth/decorators/roles.decorator';
import { RoleCode } from '../auth/schemas/role.schema';
import { ProtectedRequest } from '../core/http/request';
import { UpdateMentorDto } from './dto/update-mentor.dto';
import { Types } from 'mongoose';
import { MongoIdTransformer } from '../common/mongoid.transformer';

@Roles([RoleCode.ADMIN])
@Controller('mentor/admin')
export class MentorAdminController {
  constructor(private readonly mentorService: MentorService) {}

  @Post()
  async create(
    @Request() request: ProtectedRequest,
    @Body() createMentorDto: CreateMentorDto,
  ) {
    return await this.mentorService.create(request.user, createMentorDto);
  }

  @Put('id/:id')
  async update(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
    @Request() request: ProtectedRequest,
    @Body() updateMentorDto: UpdateMentorDto,
  ) {
    return await this.mentorService.update(request.user, id, updateMentorDto);
  }

  @Delete('id/:id')
  async delete(@Param('id', MongoIdTransformer) id: Types.ObjectId) {
    return await this.mentorService.delete(id);
  }
}
