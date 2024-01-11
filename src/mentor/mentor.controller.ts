import { Controller, Get, Param, Request } from '@nestjs/common';
import { MentorService } from './mentor.service';
import { Types } from 'mongoose';
import { ProtectedRequest } from '../core/http/request';
import { MongoIdValidationPipe } from '../utils/mongoid.pipe';
import { MentorDto } from './dto/mentor.dto';

@Controller('mentor')
export class MentorController {
  constructor(private readonly mentorService: MentorService) {}

  @Get('id/:id')
  async findOne(
    @Param('id', MongoIdValidationPipe) id: string,
    @Request() request: ProtectedRequest,
  ): Promise<MentorDto> {
    return this.mentorService.findMentor(new Types.ObjectId(id), request.user);
  }
}
