import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ItemsService } from './items.service';
import type { Item } from './items.service';

class CreateItemDto {
  name: string;
  description: string;
  price: number;
}

@Controller('items')
export class ItemsController {
  constructor(private readonly itemsService: ItemsService) {}

  /**
   * GET /api/items
   * Returns all items. In Phase 5, we'll add a Prometheus histogram
   * here to track response time percentiles (p50, p95, p99).
   */
  @Get()
  findAll(): Item[] {
    return this.itemsService.findAll();
  }

  /**
   * GET /api/items/:id
   * Returns a single item. 404 if not found.
   * This 404 path is used in Phase 5 to demo error-rate alerting.
   */
  @Get(':id')
  findOne(@Param('id') id: string): Item {
    return this.itemsService.findOne(id);
  }

  /**
   * POST /api/items
   * Creates a new item. Used in smoke tests in the Jenkins pipeline (Phase 4).
   */
  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() createItemDto: CreateItemDto): Item {
    return this.itemsService.create(createItemDto);
  }
}
