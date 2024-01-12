import { Controller, Get, NotFoundException, Param } from '@nestjs/common';
import { Types } from 'mongoose';
import { MongoIdTransformer } from '../common/mongoid.transformer';
import { MentorService } from './mentor.service';
import { MentorInfoDto } from './dto/mentor-info.dto';

@Controller('mentor')
export class MentorController {
  constructor(private readonly mentorService: MentorService) {}

  @Get('id/:id')
  async findOne(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
  ): Promise<MentorInfoDto> {
    const mentor = await this.mentorService.findById(id);
    if (!mentor) throw new NotFoundException('Mentor Not Found');
    return new MentorInfoDto(mentor);
  }
}
