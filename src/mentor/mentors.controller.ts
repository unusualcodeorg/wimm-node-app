import { Controller, Get, Query } from '@nestjs/common';
import { MentorService } from './mentor.service';
import { MentorInfoDto } from './dto/mentor-info.dto';
import { PaginationDto } from '../common/pagination.dto';

@Controller('mentors')
export class MentorsController {
  constructor(private readonly mentorService: MentorService) {}

  @Get('latest')
  async findLatest(
    @Query() paginationDto: PaginationDto,
  ): Promise<MentorInfoDto[]> {
    return this.mentorService.findMentorsPaginated(paginationDto);
  }
}
